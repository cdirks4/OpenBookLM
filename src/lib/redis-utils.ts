import { getRedisClient } from "./redis";

// Cache TTL in seconds (e.g., 1 hour)
const DEFAULT_TTL = 3600;

/**
 * Set a value in Redis with optional TTL
 */
export async function setCacheValue(
  key: string,
  value: any,
  ttl = DEFAULT_TTL
) {
  const redis = getRedisClient();
  if (!redis) return;

  const serializedValue = JSON.stringify(value);
  await redis.setex(key, ttl, serializedValue);
}

/**
 * Get a value from Redis
 */
export async function getCacheValue<T>(key: string): Promise<T | null> {
  const redis = getRedisClient();
  if (!redis) return null;

  const value = await redis.get(key);
  if (!value) return null;
  return JSON.parse(value) as T;
}

/**
 * Delete a value from Redis
 */
export async function deleteCacheValue(key: string) {
  const redis = getRedisClient();
  if (!redis) return;

  await redis.del(key);
}

/**
 * Cache function results
 */
export async function cacheResult<T>(
  key: string,
  fn: () => Promise<T>,
  ttl = DEFAULT_TTL
): Promise<T> {
  const redis = getRedisClient();
  if (!redis) {
    // If Redis is not available, just execute the function
    return fn();
  }

  const cached = await getCacheValue<T>(key);
  if (cached) return cached;

  const result = await fn();
  await setCacheValue(key, result, ttl);
  return result;
}

/**
 * Rate limiting utility
 */
export async function checkRateLimit(
  key: string,
  limit: number,
  window: number
): Promise<boolean> {
  const redis = getRedisClient();
  if (!redis) {
    // If Redis is not available, allow the request
    return true;
  }

  const current = await redis.incr(key);
  if (current === 1) {
    await redis.expire(key, window);
  }
  return current <= limit;
}

/**
 * Lock utility for distributed operations
 */
export async function acquireLock(key: string, ttl = 30): Promise<boolean> {
  const redis = getRedisClient();
  if (!redis) {
    // If Redis is not available, assume lock is acquired
    return true;
  }

  // Use SET NX (only set if not exists) with expiry
  const result = await redis.set(`lock:${key}`, Date.now(), "EX", ttl, "NX");
  return result === "OK";
}

/**
 * Release a previously acquired lock
 */
export async function releaseLock(key: string): Promise<void> {
  const redis = getRedisClient();
  if (!redis) return;

  await redis.del(`lock:${key}`);
}
export async function setChatHistory(
  userId: string,
  notebookId: string,
  messages: any[]
) {
  try {
    const redis = getRedisClient();
    if (!redis) return;

    const key = `chat:${userId}:${notebookId}`;
    const jsonString = JSON.stringify(messages);
    console.log("Storing messages:", { key, jsonString });
    await redis.set(key, jsonString);
    // Set expiration to 24 hours
    await redis.expire(key, 60 * 60 * 24);
  } catch (error) {
    console.error("Error in setChatHistory:", error);
    throw error;
  }
}

export async function getChatHistory(userId: string, notebookId: string) {
  try {
    const redis = getRedisClient();
    if (!redis) return;
    const key = `chat:${userId}:${notebookId}`;
    const history = await redis.get(key);
    console.log("Retrieved history:", { key, history, type: typeof history });

    if (!history) return [];

    if (typeof history === "object") {
      return history;
    }

    try {
      return JSON.parse(history as string);
    } catch (parseError) {
      console.error("Error parsing chat history:", parseError);
      console.error("Raw history:", history);
      return [];
    }
  } catch (error) {
    console.error("Error in getChatHistory:", error);
    return [];
  }
}

export async function clearChatHistory(userId: string, notebookId: string) {
  try {
    const redis = getRedisClient();
    if (!redis) return;
    const key = `chat:${userId}:${notebookId}`;
    await redis.del(key);
  } catch (error) {
    console.error("Error in clearChatHistory:", error);
    throw error;
  }
}

export async function setUserNotebook(
  userId: string,
  notebookId: string,
  notebook: any
) {
  try {
    const redis = getRedisClient();
    if (!redis) return;
    const key = `notebook:${userId}:${notebookId}`;
    const jsonString = JSON.stringify(notebook);
    console.log("Storing notebook:", { key, jsonString });
    await redis.set(key, jsonString);
    // Set expiration to 7 days
    await redis.expire(key, 60 * 60 * 24 * 7);
  } catch (error) {
    console.error("Error in setUserNotebook:", error);
    throw error;
  }
}

export async function getUserNotebook(userId: string, notebookId: string) {
  try {
    const redis = getRedisClient();
    if (!redis) return;
    const key = `notebook:${userId}:${notebookId}`;
    const notebook = await redis.get(key);
    console.log("Retrieved notebook:", {
      key,
      notebook,
      type: typeof notebook,
    });

    if (!notebook) return null;

    if (typeof notebook === "object") {
      return notebook;
    }

    try {
      return JSON.parse(notebook as string);
    } catch (parseError) {
      console.error("Error parsing notebook:", parseError);
      console.error("Raw notebook:", notebook);
      return null;
    }
  } catch (error) {
    console.error("Error in getUserNotebook:", error);
    return null;
  }
}

export async function setAllNotebooks(userId: string, notebooks: any[]) {
  try {
    const redis = getRedisClient();
    if (!redis) return;
    const key = `notebooks:${userId}`;
    const jsonString = JSON.stringify(notebooks);
    console.log("Storing all notebooks:", { key, count: notebooks.length });
    await redis.set(key, jsonString);
    // Set expiration to 24 hours
    await redis.expire(key, 60 * 60 * 24);
  } catch (error) {
    console.error("Error in setAllNotebooks:", error);
    throw error;
  }
}

export async function getAllNotebooks(userId: string) {
  try {
    const redis = getRedisClient();
    if (!redis) return;
    const key = `notebooks:${userId}`;
    const notebooks = await redis.get(key);
    console.log("Retrieved notebooks:", {
      key,
      count: notebooks ? JSON.parse(notebooks as string).length : 0,
    });

    if (!notebooks) return null;

    if (typeof notebooks === "object") {
      return notebooks;
    }

    try {
      return JSON.parse(notebooks as string);
    } catch (parseError) {
      console.error("Error parsing notebooks:", parseError);
      return null;
    }
  } catch (error) {
    console.error("Error in getAllNotebooks:", error);
    return null;
  }
}
