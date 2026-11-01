use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};

#[derive(Debug)]
pub struct Request {
    pub head: String,
    pub body: Vec<u8>,
}
pub struct Reply {
    pub status: u16,
    pub mime: &'static str,
    pub body: Vec<u8>,
    pub headers: Vec<(String, String)>,
}
impl Reply {
    pub fn json(value: serde_json::Value) -> Self {
        Self {
            status: 200,
            mime: "application/json",
            body: serde_json::to_vec(&value).unwrap(),
            headers: Vec::new(),
        }
    }
    #[allow(dead_code)] // Shared support is compiled separately by JSON-only test targets.
    pub fn sse(body: &str) -> Self {
        Self {
            status: 200,
            mime: "text/event-stream",
            body: body.as_bytes().to_vec(),
            headers: Vec::new(),
        }
    }
}

pub async fn read(socket: &mut tokio::net::TcpStream) -> Request {
    let mut bytes = Vec::new();
    let mut buffer = [0; 4096];
    let (end, length) = loop {
        let count = socket.read(&mut buffer).await.unwrap();
        assert_ne!(count, 0);
        bytes.extend_from_slice(&buffer[..count]);
        if let Some(start) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&bytes[..start]);
            let length = head
                .lines()
                .find_map(|l| {
                    l.to_lowercase()
                        .strip_prefix("content-length:")
                        .and_then(|s| s.trim().parse::<usize>().ok())
                })
                .unwrap_or(0);
            break (start + 4, length);
        }
    };
    while bytes.len() < end + length {
        let count = socket.read(&mut buffer).await.unwrap();
        assert_ne!(count, 0);
        bytes.extend_from_slice(&buffer[..count]);
    }
    Request {
        head: String::from_utf8(bytes[..end].into()).unwrap(),
        body: bytes[end..end + length].into(),
    }
}

pub async fn server(
    count: usize,
    mut responder: impl FnMut(usize, &Request) -> Reply + Send + 'static,
) -> (String, tokio::task::JoinHandle<Vec<Request>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let handle = tokio::spawn(async move {
        let mut requests = Vec::new();
        for index in 0..count {
            let (mut socket, _) = listener.accept().await.unwrap();
            let request = read(&mut socket).await;
            let reply = responder(index, &request);
            let mut head = format!(
                "HTTP/1.1 {} Test\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n",
                reply.status,
                reply.mime,
                reply.body.len()
            );
            for (name, value) in reply.headers {
                head.push_str(&format!("{name}: {value}\r\n"));
            }
            head.push_str("\r\n");
            socket.write_all(head.as_bytes()).await.unwrap();
            // Write very small chunks so the transport can split JSON, UTF-8 and CRLF.
            let chunk_size = if reply.mime == "text/event-stream" {
                3
            } else {
                64 * 1024
            };
            for chunk in reply.body.chunks(chunk_size) {
                if socket.write_all(chunk).await.is_err() {
                    break;
                }
                tokio::task::yield_now().await;
            }
            requests.push(request);
        }
        requests
    });
    (base, handle)
}
