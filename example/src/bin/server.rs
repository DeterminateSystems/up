use std::{net::SocketAddr, pin::Pin, time::Duration};

use greeter::greeter::v1::{
    greeter_service_server::{GreeterService, GreeterServiceServer},
    SayHelloRequest, SayHelloResponse, StreamGreetingsRequest, StreamGreetingsResponse,
    FILE_DESCRIPTOR_SET,
};
use tokio_stream::{wrappers::ReceiverStream, Stream};
use tonic::{transport::Server, Request, Response, Status};

#[derive(Default)]
struct Greeter;

type GreetStream =
    Pin<Box<dyn Stream<Item = Result<StreamGreetingsResponse, Status>> + Send + 'static>>;

#[tonic::async_trait]
impl GreeterService for Greeter {
    async fn say_hello(
        &self,
        req: Request<SayHelloRequest>,
    ) -> Result<Response<SayHelloResponse>, Status> {
        let name = req.into_inner().name;
        let message = if name.is_empty() {
            "hello, stranger".into()
        } else {
            format!("hello there, {name}")
        };
        tracing::info!(%name, "say_hello");
        Ok(Response::new(SayHelloResponse { message }))
    }

    type StreamGreetingsStream = GreetStream;

    async fn stream_greetings(
        &self,
        req: Request<StreamGreetingsRequest>,
    ) -> Result<Response<Self::StreamGreetingsStream>, Status> {
        let StreamGreetingsRequest { name, count } = req.into_inner();
        let count = count.clamp(1, 100);
        tracing::info!(%name, %count, "stream_greetings");

        let (tx, rx) = tokio::sync::mpsc::channel(8);
        tokio::spawn(async move {
            for i in 1..=count {
                let msg = StreamGreetingsResponse {
                    message: format!("hello #{i}, {name}"),
                };
                if tx.send(Ok(msg)).await.is_err() {
                    break; // client disconnected
                }
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        });

        Ok(Response::new(Box::pin(ReceiverStream::new(rx))))
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    let addr: SocketAddr = "127.0.0.1:50051".parse()?;

    let reflection = tonic_reflection::server::Builder::configure()
        .register_encoded_file_descriptor_set(FILE_DESCRIPTOR_SET)
        .build_v1()?;

    tracing::info!(%addr, "greeter listening");

    Server::builder()
        .add_service(GreeterServiceServer::new(Greeter))
        .add_service(reflection)
        .serve(addr)
        .await?;

    Ok(())
}
