use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, RwLock};
use tokio::time::sleep;

pub struct BatchProcessor<T, R> {
    #[allow(dead_code)]
    batch_size: usize,
    #[allow(dead_code)]
    timeout: Duration,
    #[allow(dead_code)]
    processor: Arc<dyn Fn(Vec<T>) -> R + Send + Sync>,
    sender: mpsc::UnboundedSender<T>,
    results: Arc<RwLock<Vec<R>>>,
}

impl<T, R> BatchProcessor<T, R>
where
    T: Send + 'static,
    R: Send + Sync + Clone + 'static,
{

    pub fn new<F>(
        batch_size: usize,
        timeout: Duration,
        processor: F,
    ) -> Self
    where
        F: Fn(Vec<T>) -> R + Send + Sync + 'static,
    {
        let (sender, mut receiver) = mpsc::unbounded_channel::<T>();
        let processor = Arc::new(processor);
        let results = Arc::new(RwLock::new(Vec::new()));

        let processor_clone = Arc::clone(&processor);
        let results_clone = Arc::clone(&results);

        tokio::spawn(async move {
            let mut batch = Vec::with_capacity(batch_size);
            let mut last_process = Instant::now();

            loop {
                tokio::select! {

                    item = receiver.recv() => {
                        match item {
                            Some(item) => {
                                batch.push(item);

                                if batch.len() >= batch_size {
                                    let result = processor_clone(std::mem::take(&mut batch));
                                    results_clone.write().await.push(result);
                                    last_process = Instant::now();
                                }
                            }
                            None => break,
                        }
                    }

                    _ = sleep(timeout) => {
                        if !batch.is_empty() && last_process.elapsed() >= timeout {
                            let result = processor_clone(std::mem::take(&mut batch));
                            results_clone.write().await.push(result);
                            last_process = Instant::now();
                        }
                    }
                }
            }

            if !batch.is_empty() {
                let result = processor_clone(batch);
                results_clone.write().await.push(result);
            }
        });

        Self {
            batch_size,
            timeout,
            processor,
            sender,
            results,
        }
    }

    pub fn add(&self, item: T) -> Result<(), mpsc::error::SendError<T>> {
        self.sender.send(item)
    }

    pub async fn get_results(&self) -> Vec<R> {
        let results = self.results.read().await;
        results.clone()
    }

    pub async fn clear_results(&self) {
        self.results.write().await.clear();
    }
}

pub struct AudioMetricsBatcher {
    processor: BatchProcessor<AudioMetric, AudioMetricsSummary>,
}

#[derive(Debug, Clone)]
pub struct AudioMetric {
    pub timestamp: Instant,
    pub chunk_id: u64,
    pub sample_count: usize,
    pub duration_ms: f64,
    pub average_level: f32,
}

#[derive(Debug, Clone)]
pub struct AudioMetricsSummary {
    pub total_chunks: usize,
    pub total_samples: usize,
    pub total_duration_ms: f64,
    pub average_level: f32,
    pub timespan: Duration,
    pub chunks_per_second: f64,
}

impl AudioMetricsBatcher {

    pub fn new() -> Self {
        let processor = BatchProcessor::new(
            50,
            Duration::from_secs(5),
            |metrics: Vec<AudioMetric>| {
                if metrics.is_empty() {
                    return AudioMetricsSummary {
                        total_chunks: 0,
                        total_samples: 0,
                        total_duration_ms: 0.0,
                        average_level: 0.0,
                        timespan: Duration::from_secs(0),
                        chunks_per_second: 0.0,
                    };
                }

                let total_chunks = metrics.len();
                let total_samples: usize = metrics.iter().map(|m| m.sample_count).sum();
                let total_duration_ms: f64 = metrics.iter().map(|m| m.duration_ms).sum();
                let average_level: f32 = metrics.iter().map(|m| m.average_level).sum::<f32>() / total_chunks as f32;

                let first_timestamp = metrics.first().unwrap().timestamp;
                let last_timestamp = metrics.last().unwrap().timestamp;
                let timespan = last_timestamp.duration_since(first_timestamp);

                let chunks_per_second = if timespan.as_secs_f64() > 0.0 {
                    total_chunks as f64 / timespan.as_secs_f64()
                } else {
                    0.0
                };

                AudioMetricsSummary {
                    total_chunks,
                    total_samples,
                    total_duration_ms,
                    average_level,
                    timespan,
                    chunks_per_second,
                }
            },
        );

        Self { processor }
    }

    pub fn add_metric(&self, metric: AudioMetric) -> Result<(), mpsc::error::SendError<AudioMetric>> {
        self.processor.add(metric)
    }

    pub async fn get_summaries(&self) -> Vec<AudioMetricsSummary> {
        self.processor.get_results().await
    }

    pub async fn clear_summaries(&self) {
        self.processor.clear_results().await
    }
}

impl Default for AudioMetricsBatcher {
    fn default() -> Self {
        Self::new()
    }
}

#[macro_export]
macro_rules! batch_audio_metric {
    ($batcher:expr, $chunk_id:expr, $sample_count:expr, $duration_ms:expr, $level:expr) => {
        if let Some(batcher) = $batcher {
            let metric = $crate::audio::batch_processor::AudioMetric {
                timestamp: std::time::Instant::now(),
                chunk_id: $chunk_id,
                sample_count: $sample_count,
                duration_ms: $duration_ms,
                average_level: $level,
            };
            let _ = batcher.add_metric(metric);
        }
    };
}