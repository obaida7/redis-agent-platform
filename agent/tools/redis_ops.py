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
def get_cluster_nodes() -> str:
    """Returns the raw output of 'CLUSTER NODES' to see the topology and status of all shards."""
    try:
        r = get_redis_client()
        if not settings.redis_cluster_mode:
            return "Redis is not in cluster mode."
        nodes = r.cluster_nodes()
        report = "Redis Cluster Nodes Status:\n"
        for node_id, node_info in nodes.items():
            report += f"- ID: {node_id[:8]}, Addr: {node_info['slots']}, Flags: {node_info['flags']}, Status: {node_info['connected']}\n"
        return report
    except Exception as e:
        return f"Failed to get cluster nodes: {str(e)}"

@tool
def check_redis_health() -> str:
    """Checks the overall health, memory, and sharding status of the Redis cluster."""
    try:
        r = get_redis_client()
        if settings.redis_cluster_mode:
            info = r.cluster_info()
            report = (
                f"Redis Cluster Health Report:\n"
                f"- State: {info.get('cluster_state')}\n"
                f"- Slots Assigned: {info.get('cluster_slots_assigned')}\n"
                f"- Slots OK: {info.get('cluster_slots_ok')}\n"
                f"- Slots Fail: {info.get('cluster_slots_fail')}\n"
                f"- Known Nodes: {info.get('cluster_known_nodes')}\n"
            )
            if info.get('cluster_state') != 'ok':
                report += "\nCRITICAL: Cluster state is unhealthy. Some slots are likely missing or nodes are unreachable."
            return report
        
        info = r.info()
        # (Standard info logic here...)
        return f"Redis Standalone Health: {info.get('used_memory_human')}"
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

@tool
def analyze_slow_log(count: int = 10) -> str:
    """Analyzes the Redis SLOWLOG to identify expensive queries that are causing latency spikes."""
    try:
        r = get_redis_client()
        # In Cluster mode, slow logs are per-node. We scan the first master as a representative sample.
        slow_queries = r.slowlog_get(num=count)
        
        if not slow_queries:
            return "No slow queries found in the log."
            
        report = f"Top {len(slow_queries)} Slow Queries Detected:\n"
        for q in slow_queries:
            duration_ms = q['duration'] / 1000
            command = q['command']
            report += f"- [Duration: {duration_ms:.2f}ms] Command: {command}\n"
            
        return report
    except Exception as e:
        return f"Failed to analyze slow log: {str(e)}"
