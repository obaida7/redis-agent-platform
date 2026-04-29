import redis
from langchain.tools import tool
from core.config import settings

from redis.cluster import RedisCluster

def get_redis_client():
    if settings.redis_cluster_mode:
        return RedisCluster(
            host=settings.redis_host,
            port=settings.redis_port,
            password=settings.redis_password,
            decode_responses=True,
            skip_full_coverage_check=True
        )
    return redis.Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        password=settings.redis_password,
        decode_responses=True
    )

@tool
def check_redis_health() -> str:
    """Checks the overall health, memory fragmentation, and connected clients of the Redis database."""
    try:
        r = get_redis_client()
        info = r.info()
        
        # Extract important metrics
        used_memory = info.get('used_memory_human', 'N/A')
        peak_memory = info.get('used_memory_peak_human', 'N/A')
        connected_clients = info.get('connected_clients', 'N/A')
        uptime_days = info.get('uptime_in_days', 'N/A')
        frag_ratio = info.get('mem_fragmentation_ratio', 'N/A')
        
        report = (
            f"Redis Health Report:\n"
            f"- Uptime: {uptime_days} days\n"
            f"- Connected Clients: {connected_clients}\n"
            f"- Used Memory: {used_memory} (Peak: {peak_memory})\n"
            f"- Fragmentation Ratio: {frag_ratio}\n"
        )
        
        if isinstance(frag_ratio, (int, float)) and float(frag_ratio) > 1.5:
            report += "\nWARNING: Memory fragmentation is high (>1.5). Consider restarting instances or defragmentation."
            
        return report
    except Exception as e:
        return f"Failed to check Redis health: {str(e)}"

@tool
def flush_stale_data(db_index: int = 0) -> str:
    """Flushes all keys in the specified database. Use with EXTREME CAUTION during incidents only."""
    try:
        r = get_redis_client()
        r.flushdb()
        return "Successfully flushed stale data from database."
    except Exception as e:
        return f"Failed to flush data: {str(e)}"

@tool
def detect_noisy_neighbor() -> str:
    """Detects 'noisy neighbor' connections by identifying clients consuming excessive memory or exhibiting high idle times."""
    try:
        r = get_redis_client()
        clients = r.client_list()
        
        abusive_clients = []
        for client in clients:
            # Check for excessive memory usage (>10MB) or unusually long idle times with high multi-commands
            mem_usage = int(client.get('tot-mem', 0))
            if mem_usage > 10_000_000:
                abusive_clients.append({
                    "id": client.get("id"),
                    "addr": client.get("addr"),
                    "mem": mem_usage,
                    "age": client.get("age"),
                    "idle": client.get("idle")
                })
        
        if not abusive_clients:
            return "No noisy neighbors detected based on memory consumption."
        
        report = "Detected Potential Noisy Neighbors:\n"
        for c in abusive_clients:
            report += f"- Client ID: {c['id']}, Address: {c['addr']}, Memory: {c['mem']} bytes, Idle: {c['idle']}s\n"
        
        return report
    except Exception as e:
        return f"Failed to detect noisy neighbors: {str(e)}"

@tool
def mitigate_noisy_neighbor(client_id: str) -> str:
    """Kills the connection of a specific noisy neighbor client by their client_id."""
    try:
        r = get_redis_client()
        r.execute_command('CLIENT', 'KILL', 'ID', client_id)
        return f"Successfully disconnected noisy neighbor client with ID: {client_id}."
    except Exception as e:
        return f"Failed to mitigate noisy neighbor (ID: {client_id}): {str(e)}"

@tool
def detect_cache_stampede() -> str:
    """Simulates detecting a cache stampede by identifying keys with high query rates and imminent expirations."""
    try:
        # In a real environment, we would use Redis keyspace notifications, Redis-cli --hotkeys, or Prometheus metrics
        # Here we simulate the heuristic detection:
        r = get_redis_client()
        
        # Simulating a cache stampede detection
        report = (
            "Cache Stampede Analysis:\n"
            "- Hotkey detected: 'app:feature_flags' (Query rate: 5000 req/sec)\n"
            "- Expiration status: TTL is critically low (< 2 seconds)\n"
            "- Recommendation: Apply jitter to the TTL or implement a distributed lock for regeneration."
        )
        return report
    except Exception as e:
        return f"Failed to detect cache stampede: {str(e)}"

@tool
def apply_jitter_or_lock(key: str) -> str:
    """Applies a probabilistic expiration (jitter) to a specified hot key to mitigate a cache stampede."""
    try:
        r = get_redis_client()
        # In reality, we'd add random variance to the TTL
        # e.g., EXPIRE key (base_ttl + random(0, 10))
        # For demonstration:
        current_ttl = r.ttl(key)
        if current_ttl <= 0:
            return f"Key '{key}' does not exist or has no TTL."
        
        # Add 30-60 seconds of jitter
        import random
        jitter = random.randint(30, 60)
        new_ttl = current_ttl + jitter
        r.expire(key, new_ttl)
        
        return f"Successfully applied jitter to key '{key}'. New TTL is {new_ttl} seconds."
    except Exception as e:
        return f"Failed to apply jitter to '{key}': {str(e)}"
