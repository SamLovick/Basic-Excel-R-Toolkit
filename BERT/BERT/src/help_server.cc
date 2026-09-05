/**
 * Copyright (c) 2026 Structured Data, LLC
 *
 * This file is part of BERT.
 *
 * BERT is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * BERT is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with BERT.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "stdafx.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <fstream>
#include <sstream>
#include <string>

#include "help_server.h"
#include "debug_functions.h"

#pragma comment(lib, "ws2_32.lib")

namespace {

  SOCKET listen_socket = INVALID_SOCKET;
  HANDLE server_thread = 0;
  int server_port = 0;
  std::string server_root;

  /**
   * we serve one flat directory of generated pages, so the only names we
   * accept are the ones we generate: ascii word characters, dots, dashes,
   * ending in .html. that rules out directory traversal, unc paths, drive
   * letters and anything with a query string, without having to reason
   * about path canonicalization.
   */
  bool ValidPageName(const std::string &name) {

    if (name.length() < 6 || name.length() > 128) return false;
    if (name.compare(name.length() - 5, 5, ".html")) return false;
    if (name[0] == '.' || name[0] == '-') return false;

    for (auto c : name) {
      bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_';
      if (!ok) return false;
    }

    // no ".." even though the characters are legal on their own
    if (name.find("..") != std::string::npos) return false;

    return true;
  }

  void SendAll(SOCKET socket, const std::string &data) {
    const char *pointer = data.c_str();
    int remaining = (int)data.length();
    while (remaining > 0) {
      int sent = send(socket, pointer, remaining, 0);
      if (sent <= 0) return;
      pointer += sent;
      remaining -= sent;
    }
  }

  void SendResponse(SOCKET socket, const char *status, const char *content_type, const std::string &body) {
    std::stringstream response;
    response << "HTTP/1.1 " << status << "\r\n";
    response << "Content-Type: " << content_type << "\r\n";
    response << "Content-Length: " << body.length() << "\r\n";

    // these pages are regenerated whenever functions are registered, so a
    // cached copy would show yesterday's help after an edit

    response << "Cache-Control: no-store\r\n";
    response << "Connection: close\r\n";
    response << "\r\n";
    response << body;
    SendAll(socket, response.str());
  }

  /** reads the request line; we don't care about headers or bodies */
  bool ReadRequestLine(SOCKET socket, std::string &line) {

    char buffer[2048];
    int length = 0;

    while (length < (int)sizeof(buffer) - 1) {
      int read = recv(socket, buffer + length, (int)(sizeof(buffer) - 1 - length), 0);
      if (read <= 0) break;
      length += read;
      buffer[length] = 0;
      char *end = strstr(buffer, "\r\n");
      if (end) {
        line.assign(buffer, end - buffer);
        return true;
      }
    }

    return false;
  }

  void HandleConnection(SOCKET socket) {

    std::string request;
    if (!ReadRequestLine(socket, request)) return;

    // GET /page.html HTTP/1.1

    if (request.compare(0, 4, "GET ")) {
      SendResponse(socket, "405 Method Not Allowed", "text/plain", "no");
      return;
    }

    size_t start = 4;
    size_t end = request.find(' ', start);
    if (end == std::string::npos) end = request.length();

    std::string path = request.substr(start, end - start);
    if (path.length() && path[0] == '/') path = path.substr(1);

    size_t query = path.find_first_of("?#");
    if (query != std::string::npos) path = path.substr(0, query);

    if (!ValidPageName(path)) {
      SendResponse(socket, "404 Not Found", "text/plain", "no such help page");
      return;
    }

    std::string file = server_root;
    file.append(path);

    std::ifstream stream(file, std::ios::binary);
    if (!stream.good()) {
      SendResponse(socket, "404 Not Found", "text/plain", "no such help page");
      return;
    }

    std::stringstream body;
    body << stream.rdbuf();
    SendResponse(socket, "200 OK", "text/html; charset=utf-8", body.str());
  }

  DWORD WINAPI ServerThread(LPVOID) {

    while (true) {
      SOCKET client = accept(listen_socket, 0, 0);
      if (client == INVALID_SOCKET) break; // closed, or failed: either way we're done

      HandleConnection(client);

      shutdown(client, SD_SEND);
      closesocket(client);
    }

    return 0;
  }

}

int HelpServer::Start(const std::string &root) {

  if (server_port) return server_port;

  WSADATA wsa_data;
  if (WSAStartup(MAKEWORD(2, 2), &wsa_data)) {
    DebugOut("help server: WSAStartup failed\n");
    return 0;
  }

  server_root = root;

  listen_socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listen_socket == INVALID_SOCKET) {
    DebugOut("help server: could not create socket\n");
    return 0;
  }

  // loopback, and a port the system picks: nothing outside this machine
  // can reach it, and we don't have to guess at a free port

  sockaddr_in address;
  ZeroMemory(&address, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_port = 0;
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  if (bind(listen_socket, (sockaddr*)&address, sizeof(address)) == SOCKET_ERROR
      || listen(listen_socket, 8) == SOCKET_ERROR) {
    DebugOut("help server: could not listen\n");
    closesocket(listen_socket);
    listen_socket = INVALID_SOCKET;
    return 0;
  }

  int length = sizeof(address);
  if (getsockname(listen_socket, (sockaddr*)&address, &length) == SOCKET_ERROR) {
    DebugOut("help server: could not read the port\n");
    closesocket(listen_socket);
    listen_socket = INVALID_SOCKET;
    return 0;
  }

  server_port = ntohs(address.sin_port);

  server_thread = CreateThread(0, 0, ServerThread, 0, 0, 0);
  if (!server_thread) {
    DebugOut("help server: could not start the thread\n");
    closesocket(listen_socket);
    listen_socket = INVALID_SOCKET;
    server_port = 0;
    return 0;
  }

  DebugOut("help server: listening on 127.0.0.1:%d\n", server_port);
  return server_port;
}

int HelpServer::port() {
  return server_port;
}

std::string HelpServer::UrlFor(const std::string &file) {

  if (!server_port || !file.length()) return "";

  std::stringstream url;
  url << "http://127.0.0.1:" << server_port << "/" << file;
  return url.str();
}

void HelpServer::Stop() {

  if (listen_socket != INVALID_SOCKET) {
    closesocket(listen_socket); // unblocks accept, which ends the thread
    listen_socket = INVALID_SOCKET;
  }

  if (server_thread) {
    WaitForSingleObject(server_thread, 2000);
    CloseHandle(server_thread);
    server_thread = 0;
  }

  server_port = 0;
}
