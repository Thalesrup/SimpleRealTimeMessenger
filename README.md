# SimpleRealTimeMessenger

SimpleRealTimeMessenger is a basic real-time messaging server implemented in Erlang, using WebSockets to handle client connections. This project WebSocket server from scratch without external dependencies.

## Features

- Accepts WebSocket connections from clients.
- Echoes messages back to the client.
- Implements WebSocket handshake and message handling.
- Lightweight and simple to understand.

## Prerequisites

- Erlang/OTP installed on your machine.

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/yourusername/SimpleRealTimeMessenger.git
cd SimpleRealTimeMessenger
```

### Run

```bash
erlc realtime_messenger.erl => compile
erl -s realtime_messenger start_link => run at port 8089
```
### Web Implementation Example
<br>
Explore the web directory to see a fully styled real-time chat client, execute index.html