use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::collections::VecDeque;

pub struct AudioBufferPool {
    pool: Arc<Mutex<VecDeque<Vec<f32>>>>,
    max_size: usize,
    buffer_capacity: usize,
}

impl AudioBufferPool {

    pub fn new(max_size: usize, buffer_capacity: usize) -> Self {
        Self {
            pool: Arc::new(Mutex::new(VecDeque::with_capacity(max_size))),
            max_size,
            buffer_capacity,
        }
    }

    fn lock_pool(&self) -> MutexGuard<'_, VecDeque<Vec<f32>>> {
        self.pool.lock().unwrap_or_else(PoisonError::into_inner)
    }

    pub fn get_buffer(&self) -> Vec<f32> {
        let mut pool = self.lock_pool();

        match pool.pop_front() {
            Some(mut buffer) => {
                buffer.clear();
                buffer.reserve(self.buffer_capacity);
                buffer
            }
            None => {

                Vec::with_capacity(self.buffer_capacity)
            }
        }
    }

    pub fn return_buffer(&self, mut buffer: Vec<f32>) {

        buffer.clear();

        let mut pool = self.lock_pool();

        if pool.len() < self.max_size {
            pool.push_back(buffer);
        }

    }

    pub fn pool_size(&self) -> usize {
        self.lock_pool().len()
    }

    pub fn clear(&self) {
        self.lock_pool().clear();
    }
}

impl Clone for AudioBufferPool {
    fn clone(&self) -> Self {
        Self {
            pool: Arc::clone(&self.pool),
            max_size: self.max_size,
            buffer_capacity: self.buffer_capacity,
        }
    }
}

pub struct PooledBuffer {
    buffer: Option<Vec<f32>>,
    pool: AudioBufferPool,
}

impl PooledBuffer {

    pub fn new(pool: AudioBufferPool) -> Self {
        let buffer = pool.get_buffer();
        Self {
            buffer: Some(buffer),
            pool,
        }
    }

    pub fn as_mut(&mut self) -> &mut Vec<f32> {
        self.buffer.as_mut().expect("Buffer should always be available")
    }

    pub fn as_ref(&self) -> &Vec<f32> {
        self.buffer.as_ref().expect("Buffer should always be available")
    }

    pub fn into_inner(mut self) -> Vec<f32> {
        self.buffer.take().expect("Buffer should always be available")
    }
}

impl Drop for PooledBuffer {
    fn drop(&mut self) {
        if let Some(buffer) = self.buffer.take() {
            self.pool.return_buffer(buffer);
        }
    }
}

impl std::ops::Deref for PooledBuffer {
    type Target = Vec<f32>;

    fn deref(&self) -> &Self::Target {
        self.as_ref()
    }
}

impl std::ops::DerefMut for PooledBuffer {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.as_mut()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_buffer_pool() {
        let pool = AudioBufferPool::new(3, 1024);
        assert_eq!(pool.pool_size(), 0);

        let buffer = pool.get_buffer();
        assert_eq!(buffer.capacity(), 1024);
        pool.return_buffer(buffer);
        assert_eq!(pool.pool_size(), 1);

        let buffer2 = pool.get_buffer();
        assert_eq!(pool.pool_size(), 0);
        pool.return_buffer(buffer2);
    }

    #[test]
    fn test_pooled_buffer_raii() {
        let pool = AudioBufferPool::new(2, 512);

        {
            let mut pooled = PooledBuffer::new(pool.clone());
            pooled.push(1.0);
            pooled.push(2.0);
            assert_eq!(pooled.len(), 2);
        }

        assert_eq!(pool.pool_size(), 1);
    }

    #[test]
    fn test_pool_max_size() {
        let pool = AudioBufferPool::new(2, 256);

        let buf1 = pool.get_buffer();
        let buf2 = pool.get_buffer();
        let buf3 = pool.get_buffer();

        pool.return_buffer(buf1);
        pool.return_buffer(buf2);
        pool.return_buffer(buf3);

        assert_eq!(pool.pool_size(), 2);
    }
}