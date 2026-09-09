#include "bluetooth_connection.h"
#include <iostream>

namespace flutter_classic_bluetooth {

BluetoothConnection::BluetoothConnection(int id, SOCKET socket, const std::string& address)
    : id_(id), socket_(socket), address_(address) {}

BluetoothConnection::~BluetoothConnection() {
  Close();
}

void BluetoothConnection::StartReading(
    std::function<void(const std::vector<uint8_t>&)> on_data,
    std::function<void()> on_disconnected) {
  read_thread_ = std::thread([this, on_data, on_disconnected]() {
    char buffer[1024];
    while (connected_.load()) {
      int bytes_read = recv(socket_, buffer, sizeof(buffer), 0);
      if (bytes_read > 0) {
        std::vector<uint8_t> data(buffer, buffer + bytes_read);
        on_data(data);
      } else {
        break;
      }
    }
    connected_.store(false);
    on_disconnected();
  });
  read_thread_.detach();
}

bool BluetoothConnection::Write(const std::vector<uint8_t>& data) {
  if (!connected_.load()) return false;
  // send() may accept fewer bytes than it was given, especially once the
  // peer's window fills. Reporting success on a short send silently dropped
  // the tail of the payload, so keep going until it is all gone.
  const char* p = reinterpret_cast<const char*>(data.data());
  size_t remaining = data.size();
  while (remaining > 0) {
    int sent = send(socket_, p, static_cast<int>(remaining), 0);
    if (sent == SOCKET_ERROR || sent <= 0) return false;
    p += sent;
    remaining -= static_cast<size_t>(sent);
  }
  return true;
}

void BluetoothConnection::Close() {
  if (connected_.exchange(false)) {
    closesocket(socket_);
    socket_ = INVALID_SOCKET;
  }
}

}  // namespace flutter_classic_bluetooth
