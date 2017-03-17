module socketio.socketio;

import vibe.core.log;
import vibe.http.server;
import vibe.http.websockets;
import vibe.http.router;

public import
    socketio.transport: IoSocket;

import
    socketio.parameters,
    socketio.transport,
    socketio.parser,
    socketio.util;

import
    std.conv,
    std.range,
    std.algorithm,
    std.string,
    std.regex;

class SocketIo
{
    alias void delegate(IoSocket socket) Handler;

    package(socketio) {
        /// all open sockets
        IoSocket[string] m_sockets;
        /// ids of all connected clients
        bool[string] m_connected;
        /// custom connect handler
        Handler m_onConnect;
        /// user-defined settings
        Parameters m_params;
    }

    this()
    {
        m_params = new Parameters;
        urlRe = regex("^\\/([^\\/]+)\\/?([^\\/]+)?\\/?([^\\/]+)?\\/?$");
    }

    final @property Parameters parameters()
    {
        return m_params;
    }

    void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
    {
        import std.stdio;
        auto root = "/socket.io";
        if(!req.path.startsWith(root))
            return;
        auto path = req.path[root.length..$];
        auto pieces = match(path, urlRe).captures;
        auto id = pieces[3];
        req.params["transport"] = pieces[2];
        req.params["sessid"] = id;
        auto dg = id.empty ? &handleHandhakeRequest : &handleHTTPRequest;
        if (m_params.useCORS)
        {
            res.headers["Access-Control-Allow-Origin"] = "http://localhost:3000";
            res.headers["Access-Control-Allow-Credentials"] = "true";
        }
        dg(req, res);
    }

    void handleHandhakeRequest(HTTPServerRequest req, HTTPServerResponse res)
    {
        auto transports = m_params.transports.join(",");
        auto hbt = m_params.heartbeatTimeout.to!string();
        auto ct  = m_params.closeTimeout.to!string();
        string data = [generateId(), hbt, ct, transports].join(":");
        res.statusCode = HTTPStatus.OK;
        logDebug("socket.handshake: %s", data);
        res.writeBody(data, "text/plain;");
    }

    void handleHTTPRequest(HTTPServerRequest req, HTTPServerResponse res)
    {
        auto transportName = req.params["transport"];
        auto id = req.params["sessid"];

        logDebug("socket.request: %s", transportName);
        switch(transportName)
        {
        case "websocket":
            auto callback = handleWebSockets( delegate(scope websocket) {
                auto tr = new WebSocketTransport(websocket);
                auto ioSocket = new IoSocket(this, id, tr);
                onConnect(ioSocket, req, res);
                m_sockets.remove(id);
            });

            callback(req, res);
            break;

        case "xhr-polling":
            auto sock = id in m_sockets;
            IoSocket ioSocket;
            if(sock) {
                ioSocket = *sock;
            } else {
                auto tr = new XHRPollingTransport;
                ioSocket = new IoSocket(this, id, tr);
            }
            onConnect(ioSocket, req, res);
            break;

        default:
        }
    }

    void onConnection(Handler handler)
    {
        m_onConnect = handler;
    }

private:
    private {
        Regex!char urlRe;
    }

    void onConnect(IoSocket ioSocket, HTTPServerRequest req, HTTPServerResponse res)
    {
        auto id = ioSocket.id;

        if(id !in m_connected)
        {
            ioSocket.on("disconnect", () {
                m_connected.remove(id);
                m_sockets.remove(id);
                ioSocket.cleanup();
            });
            // indicate to the client that we connected
            ioSocket.schedule(Message(MessageType.connect));
            m_connected[id] = true;

            if(m_onConnect !is null)
                m_onConnect(ioSocket);
        }

        m_sockets[id] = ioSocket;

        ioSocket.setHeartbeatTimeout();

        ioSocket.m_transport.onRequest(req, res);

        ioSocket.cleanup();
    }
}
