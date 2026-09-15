#include "service_manager_plugin.h"

#include <windows.h>
#include <sddl.h>
#include <winsvc.h>

#include <string>
#include <vector>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::string WideToUtf8(const wchar_t* value) {
  if (!value) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  std::string result(size > 0 ? size : 0, '\0');
  if (size > 0) {
    WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr, nullptr);
    result.resize(size - 1);
  }
  return result;
}

std::wstring ServiceName(const EncodableValue* arguments) {
  if (!arguments) return {};
  if (const auto* value = std::get_if<std::string>(arguments)) {
    int size = MultiByteToWideChar(CP_UTF8, 0, value->c_str(), -1, nullptr, 0);
    std::wstring result(size > 0 ? size : 0, L'\0');
    if (size > 0) {
      MultiByteToWideChar(CP_UTF8, 0, value->c_str(), -1, result.data(), size);
      result.resize(size - 1);
    }
    return result;
  }
  if (const auto* map = std::get_if<EncodableMap>(arguments)) {
    for (const char* key : {"serviceName", "name"}) {
      auto it = map->find(EncodableValue(key));
      if (it != map->end()) return ServiceName(&it->second);
    }
  }
  return {};
}

const char* StatusName(DWORD status) {
  switch (status) {
    case SERVICE_STOPPED: return "stopped";
    case SERVICE_START_PENDING: return "startPending";
    case SERVICE_STOP_PENDING: return "stopPending";
    case SERVICE_RUNNING: return "running";
    case SERVICE_CONTINUE_PENDING: return "continuePending";
    case SERVICE_PAUSE_PENDING: return "pausePending";
    case SERVICE_PAUSED: return "paused";
    default: return "unknown";
  }
}

EncodableValue ServiceStatus(const SERVICE_STATUS_PROCESS& status) {
  return EncodableValue(EncodableMap{
      {EncodableValue("status"), EncodableValue(static_cast<int32_t>(status.dwCurrentState))},
      {EncodableValue("statusName"), EncodableValue(StatusName(status.dwCurrentState))},
      {EncodableValue("processId"), EncodableValue(static_cast<int32_t>(status.dwProcessId))}});
}

void ListServices(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ENUMERATE_SERVICE);
  if (!manager) {
    result->Error("OpenSCManager", "Unable to open the Service Control Manager", GetLastError());
    return;
  }

  EncodableList services;
  DWORD resume = 0;
  do {
    DWORD needed = 0, count = 0;
    EnumServicesStatusExW(manager, SC_ENUM_PROCESS_INFO, SERVICE_WIN32,
                           SERVICE_STATE_ALL, nullptr, 0, &needed, &count, &resume, nullptr);
    if (GetLastError() != ERROR_MORE_DATA && needed == 0) break;
    std::vector<BYTE> buffer(needed);
    if (!EnumServicesStatusExW(manager, SC_ENUM_PROCESS_INFO, SERVICE_WIN32,
                               SERVICE_STATE_ALL, buffer.data(), static_cast<DWORD>(buffer.size()),
                               &needed, &count, &resume, nullptr)) {
      DWORD error = GetLastError();
      CloseServiceHandle(manager);
      result->Error("EnumServicesStatusEx", "Unable to enumerate services", error);
      return;
    }
    auto* entries = reinterpret_cast<ENUM_SERVICE_STATUS_PROCESSW*>(buffer.data());
    for (DWORD i = 0; i < count; ++i) {
      services.emplace_back(EncodableMap{
          {EncodableValue("name"), EncodableValue(WideToUtf8(entries[i].lpServiceName))},
          {EncodableValue("serviceName"), EncodableValue(WideToUtf8(entries[i].lpServiceName))},
          {EncodableValue("displayName"), EncodableValue(WideToUtf8(entries[i].lpDisplayName))},
          {EncodableValue("status"), EncodableValue(static_cast<int32_t>(entries[i].ServiceStatusProcess.dwCurrentState))},
          {EncodableValue("statusName"), EncodableValue(StatusName(entries[i].ServiceStatusProcess.dwCurrentState))}});
    }
  } while (resume != 0);
  CloseServiceHandle(manager);
  result->Success(EncodableValue(std::move(services)));
}

bool IsAdministrator() {
  SID_IDENTIFIER_AUTHORITY authority = SECURITY_NT_AUTHORITY;
  PSID admin_group = nullptr;
  BOOL is_member = FALSE;
  bool result = AllocateAndInitializeSid(&authority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                         DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                         &admin_group) &&
                CheckTokenMembership(nullptr, admin_group, &is_member) &&
                is_member != FALSE;
  if (admin_group) FreeSid(admin_group);
  return result;
}

void HandleCall(const flutter::MethodCall<EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "listServices") {
    ListServices(std::move(result));
    return;
  }
  if (method == "isAdministrator") {
    result->Success(EncodableValue(IsAdministrator()));
    return;
  }

  std::wstring name = ServiceName(call.arguments());
  if (name.empty()) {
    result->Error("invalidArguments", "A service name is required");
    return;
  }
  SC_HANDLE manager = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!manager) {
    result->Error("OpenSCManager", "Unable to open the Service Control Manager", GetLastError());
    return;
  }

  if (method == "queryStatus") {
    SC_HANDLE service = OpenServiceW(manager, name.c_str(), SERVICE_QUERY_STATUS);
    SERVICE_STATUS_PROCESS status{};
    DWORD bytes = 0;
    bool ok = service && QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO,
                                               reinterpret_cast<BYTE*>(&status), sizeof(status), &bytes);
    DWORD error = ok ? ERROR_SUCCESS : GetLastError();
    if (service) CloseServiceHandle(service);
    CloseServiceHandle(manager);
    if (!ok) result->Error("QueryServiceStatus", "Unable to query service status", error);
    else result->Success(ServiceStatus(status));
    return;
  }

  if (method == "queryDisplayName") {
    SC_HANDLE service = OpenServiceW(manager, name.c_str(), SERVICE_QUERY_CONFIG);
    DWORD needed = 0;
    QueryServiceConfigW(service, nullptr, 0, &needed);
    std::vector<BYTE> buffer(needed);
    auto* config = reinterpret_cast<QUERY_SERVICE_CONFIGW*>(buffer.data());
    bool ok = service && needed > 0 &&
              QueryServiceConfigW(service, config, needed, &needed);
    DWORD error = ok ? ERROR_SUCCESS : GetLastError();
    if (service) CloseServiceHandle(service);
    CloseServiceHandle(manager);
    if (!ok) {
      result->Error("QueryServiceConfig", "Unable to query service display name",
                    error);
    } else {
      result->Success(EncodableValue(WideToUtf8(config->lpDisplayName)));
    }
    return;
  }

  DWORD access = method == "startService" ? SERVICE_START : SERVICE_STOP;
  SC_HANDLE service = OpenServiceW(manager, name.c_str(), access);
  bool ok = false;
  if (service) {
    if (method == "startService") {
      ok = StartServiceW(service, 0, nullptr) != FALSE;
      if (!ok && GetLastError() == ERROR_SERVICE_ALREADY_RUNNING) {
        ok = true;
      }
    } else if (method == "stopService") {
      SERVICE_STATUS status{};
      ok = ControlService(service, SERVICE_CONTROL_STOP, &status) != FALSE;
      if (!ok && GetLastError() == ERROR_SERVICE_NOT_ACTIVE) {
        ok = true;
      }
    }
  }
  DWORD error = ok ? ERROR_SUCCESS : GetLastError();
  if (service) CloseServiceHandle(service);
  CloseServiceHandle(manager);
  if (method != "startService" && method != "stopService") {
    result->NotImplemented();
  } else if (!ok) {
    result->Error("ServiceControl", "Unable to control service", error);
  } else {
    result->Success(EncodableValue(true));
  }
}

}  // namespace

void RegisterServiceManagerPlugin(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "service_manager/windows_services",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(HandleCall);
}
