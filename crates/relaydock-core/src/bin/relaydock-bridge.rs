use relaydock_core::{execute_bridge_command, BridgeCommand, BridgeError, BridgeResponse};
use std::io::{self, Read, Write};

fn main() {
    let (response, exit_code) = match read_command_json()
        .and_then(parse_command)
        .and_then(execute_bridge_command)
    {
        Ok(result) => (BridgeResponse::success(result), 0),
        Err(error) => (BridgeResponse::failure(error), 1),
    };

    if let Err(error) = write_response(&response) {
        let _ = writeln!(io::stderr(), "failed to write bridge response: {error}");
        std::process::exit(1);
    }

    std::process::exit(exit_code);
}

fn read_command_json() -> Result<String, BridgeError> {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if !args.is_empty() {
        return Ok(args.join(" "));
    }

    let mut input = String::new();
    io::stdin().read_to_string(&mut input).map_err(|error| {
        BridgeError::internal("Could not read bridge command", Some(error.to_string()))
    })?;

    if input.trim().is_empty() {
        return Err(BridgeError::invalid_command(
            "Bridge command input is empty",
            Some("Expected one JSON command on stdin or as a process argument.".to_string()),
        ));
    }

    Ok(input)
}

fn parse_command(input: String) -> Result<BridgeCommand, BridgeError> {
    serde_json::from_str(&input).map_err(|error| {
        BridgeError::invalid_command("Command JSON could not be parsed", Some(error.to_string()))
    })
}

fn write_response(response: &BridgeResponse) -> Result<(), serde_json::Error> {
    let stdout = io::stdout();
    let mut handle = stdout.lock();
    serde_json::to_writer(&mut handle, response)?;
    let _ = writeln!(handle);
    Ok(())
}
