use std::sync::Arc;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use log::{Level, Record};

pub struct AsyncLogger {
    sender: mpsc::UnboundedSender<LogMessage>,
    _handle: JoinHandle<()>,
}

#[derive(Debug)]
struct LogMessage {
    level: Level,
    target: String,
    message: String,
    #[allow(dead_code)]
    timestamp: std::time::Instant,
}

impl AsyncLogger {

    pub fn new(buffer_size: usize) -> Self {
        let (sender, mut receiver) = mpsc::unbounded_channel::<LogMessage>();

        let handle = tokio::spawn(async move {
            let mut buffered_messages = Vec::with_capacity(buffer_size);
            let mut last_flush = std::time::Instant::now();

            while let Some(message) = receiver.recv().await {
                buffered_messages.push(message);

                if buffered_messages.len() >= buffer_size ||
                   last_flush.elapsed().as_millis() >= 100 {
                    Self::flush_messages(&mut buffered_messages);
                    last_flush = std::time::Instant::now();
                }
            }

            if !buffered_messages.is_empty() {
                Self::flush_messages(&mut buffered_messages);
            }
        });

        Self {
            sender,
            _handle: handle,
        }
    }

    pub fn log(&self, level: Level, target: &str, message: String) {
        let log_msg = LogMessage {
            level,
            target: target.to_string(),
            message,
            timestamp: std::time::Instant::now(),
        };

        let _ = self.sender.send(log_msg);
    }

    fn flush_messages(messages: &mut Vec<LogMessage>) {
        for msg in messages.drain(..) {

            log::logger().log(&Record::builder()
                .args(format_args!("{}", msg.message))
                .level(msg.level)
                .target(&msg.target)
                .build());
        }
    }
}

static ASYNC_LOGGER: once_cell::sync::OnceCell<Arc<AsyncLogger>> = once_cell::sync::OnceCell::new();

pub fn init_async_logger() {

    if tokio::runtime::Handle::try_current().is_ok() {
        let logger = AsyncLogger::new(1000);
        ASYNC_LOGGER.set(Arc::new(logger)).ok();
    }
}

pub fn get_async_logger() -> Option<Arc<AsyncLogger>> {

    if ASYNC_LOGGER.get().is_none() && tokio::runtime::Handle::try_current().is_ok() {
        let logger = AsyncLogger::new(1000);
        let _ = ASYNC_LOGGER.set(Arc::new(logger));
    }
    ASYNC_LOGGER.get().cloned()
}

#[macro_export]
macro_rules! async_debug {
    ($($arg:tt)*) => {
        if let Some(logger) = $crate::audio::async_logger::get_async_logger() {
            logger.log(log::Level::Debug, module_path!(), format!($($arg)*));
        }
    };
}

#[macro_export]
macro_rules! async_info {
    ($($arg:tt)*) => {
        if let Some(logger) = $crate::audio::async_logger::get_async_logger() {
            logger.log(log::Level::Info, module_path!(), format!($($arg)*));
        }
    };
}

#[macro_export]
macro_rules! async_warn {
    ($($arg:tt)*) => {
        if let Some(logger) = $crate::audio::async_logger::get_async_logger() {
            logger.log(log::Level::Warn, module_path!(), format!($($arg)*));
        }
    };
}