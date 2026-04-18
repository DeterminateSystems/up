pub mod greeter {
    pub mod v1 {
        include!("gen/greeter/v1/greeter.v1.rs");
        include!("gen/greeter/v1/greeter.v1.tonic.rs");
    }
}
