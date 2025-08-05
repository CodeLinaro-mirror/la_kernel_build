// Copyright (C) 2024 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Helper wrapper for hermetic tools to wrap arguments.

#include <linux/limits.h>
#include <optional>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#include <filesystem>
#include <iostream>
#include <map>
#include <string>
#include <vector>

using std::string_literals::operator""s;

namespace {

// Template variables
constexpr bool NDEBUG = false;
constexpr std::string_view kActualExePath = "{actual_executable_path}";
constexpr std::string_view kActualExeShortPath =
    "{actual_executable_short_path}";
constexpr std::string_view kOut = "{out}";
constexpr std::string_view kPkgBinDir = "{pkg_bin_dir}";
constexpr std::string_view kPkgShort = "{pkg_short}";

// Args appended to the args from command line.
std::vector<std::string> get_append_args() { return {{append_args}}; }

// Kleaf uses bzlmod everywhere.
constexpr std::string_view kWorkspaceName = "_main";

// $(realpath /proc/self/exe)
std::filesystem::path get_my_path() {
  std::error_code ec;
  auto my_path = std::filesystem::read_symlink("/proc/self/exe", ec);
  if (ec.value() != 0) {
    std::cerr << "ERROR: read_symlink /proc/self/exe: " << ec.message()
              << std::endl;
    exit(EX_SOFTWARE);
  }
  return my_path;
}

// Get the current environment (environ) and parse it as a std::map
std::map<std::string, std::string> get_environ() {
  std::map<std::string, std::string> env_map;
  for (char **env = environ; *env != nullptr; ++env) {
    std::string env_str = *env;
    size_t pos = env_str.find('=');
    if (pos != std::string::npos) {
      std::string key = env_str.substr(0, pos);
      std::string value = env_str.substr(pos + 1);
      env_map[key] = value;
    }
  }
  return env_map;
}

// Returns the value of an environment variable or "" if not found.
std::string getenv_s(const std::map<std::string, std::string> &environ,
                     const std::string &var_name) {
  if (environ.find(var_name) != environ.end()) {
    return environ.at(var_name);
  }
  return "";
}

// Run the executable with the given arguments and environment.
[[noreturn]]
void do_exec(const std::filesystem::path &executable, int argc, char *argv[],
             const std::map<std::string, std::string> &environ) {

  // calculate args
  std::vector<char *> new_argv;
  for (int i = 0; i < argc; i++) {
    new_argv.push_back(argv[i]);
  }
  auto append_args = get_append_args();
  for (auto &append_arg : append_args) {
    new_argv.push_back(append_arg.data());
  }
  new_argv.push_back(nullptr);

  // calculate environment
  std::vector<std::string> serialized_environ_data;
  std::vector<char *> serialized_environ;
  for (const auto &[key, value] : environ) {
    serialized_environ_data.emplace_back(key + "=" + value);
  }
  for (auto &item : serialized_environ_data) {
    serialized_environ.push_back(item.data());
  }
  serialized_environ.push_back(nullptr);

  // Print debug information
  if constexpr (NDEBUG) {
    std::cerr << "DEBUG: execve:" << executable;
    for (auto &arg : new_argv) {
      if (arg != nullptr)
        std::cerr << " " << arg;
    }
    std::cerr << std::endl;
  }

  // Execute it
  execve(executable.c_str(), new_argv.data(), serialized_environ.data());
  int saved_errno = errno;
  std::cerr << "ERROR: execve: " << executable << ": " << strerror(saved_errno)
            << std::endl;
  exit(EX_SOFTWARE);
}

// Try executing the executable assuming the given runfiles directory.
void try_exec_on_runfiles(const std::filesystem::path &runfiles_dir, int argc,
                          char *argv[],
                          const std::map<std::string, std::string> &environ) {
  if constexpr (NDEBUG) {
    std::cerr << "DEBUG: trying execution on runfiles directory: "
              << runfiles_dir << std::endl;
  }
  auto candidate_executable =
      runfiles_dir / kWorkspaceName / kActualExeShortPath;
  if (!std::filesystem::exists(candidate_executable)) {
    if constexpr (NDEBUG) {
      std::cerr << "DEBUG: " << candidate_executable << " does not exist"
                << std::endl;
    }
    return;
  }
  do_exec(candidate_executable, argc, argv, environ);
}

// Returns true if s ends with suffix.
bool ends_with(const std::string_view s, const std::string_view suffix) {
  if (s.size() < suffix.size()) {
    return false;
  }
  return s.substr(s.size() - suffix.size()) == suffix;
}

// Trim suffix from s, return nullopt if s does not end with suffix.
std::optional<std::string> try_remove_suffix(const std::string_view s,
                                             const std::string_view suffix) {
  if (!ends_with(s, suffix)) {
    return std::nullopt;
  }
  return std::string(s.substr(0, s.size() - suffix.size()));
}

// Trim suffix from s, throwing an error if s does not end with suffix.
std::string remove_suffix(const std::string_view s,
                          const std::string_view suffix) {
  if (!ends_with(s, suffix)) {
    std::cerr << "ERROR: " << s << " does not end with " << suffix << std::endl;
    exit(EX_SOFTWARE);
  }
  return std::string(s.substr(0, s.size() - suffix.size()));
}
} // namespace

int main(int argc, char *argv[]) {
  auto my_path = get_my_path();
  auto environ = get_environ();

  if constexpr (NDEBUG) {
    std::cerr << "DEBUG: === EXE_DISPATCHER ===" << std::endl;
    std::cerr << "DEBUG: " << my_path;
    for (int i = 0; i < argc; i++) {
      std::cerr << " " << argv[i];
    }
    std::cerr << std::endl;
  }

  // If running directly:
  // Case 1: use RUNFILES_DIR. This has highest priority.
  auto candidate_runfiles_dir = getenv_s(environ, "RUNFILES_DIR");
  if (!candidate_runfiles_dir.empty()) {
    try_exec_on_runfiles(candidate_runfiles_dir, argc, argv, environ);
  }

  // Case 2: Use <executable_path>.runfiles.
  candidate_runfiles_dir = my_path.string() + ".runfiles";
  try_exec_on_runfiles(candidate_runfiles_dir, argc, argv, environ);

  // Case 3: Assume that <executable_path> is already in a runfiles directory.
  auto my_short = std::filesystem::path(kPkgShort) / kOut;
  auto candidate_runfiles_dir_result =
      try_remove_suffix(my_path.string(), my_short.string());
  if (candidate_runfiles_dir_result.has_value() &&
      ends_with(*candidate_runfiles_dir_result, ".runfiles")) {
    try_exec_on_runfiles(*candidate_runfiles_dir_result, argc, argv, environ);
  }

  // Case 4: Assume that <executable_path> is under an execroot (`bazel build`
  // action executing it directly).
  auto abs_out_package_path = remove_suffix(my_path.string(), kOut);
  abs_out_package_path = remove_suffix(abs_out_package_path, "/");
  std::filesystem::path execroot =
      remove_suffix(abs_out_package_path, kPkgBinDir);
  do_exec(execroot / kActualExePath, argc, argv, environ);
}
