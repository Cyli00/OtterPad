use otter_core::{migrate, storage::Storage};
use tokio_util::sync::CancellationToken;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let source = args
        .next()
        .ok_or("expected legacy root and destination root")?;
    let destination = args.next().ok_or("expected destination root")?;
    let stop_after = args.next().map(|s| s.parse::<usize>()).transpose()?;
    let token = CancellationToken::new();
    let mut storage = Storage::open(destination)?;
    let report = migrate::run(
        &mut storage,
        std::path::Path::new(&source),
        &token,
        |progress| {
            if stop_after.is_some_and(|n| progress.done >= n) {
                token.cancel();
            }
        },
    )?;
    println!("{}", serde_json::to_string(&report)?);
    Ok(())
}
