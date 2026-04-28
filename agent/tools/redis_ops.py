import redis
from langchain.tools import tool
from core.config import settings

def get_redis_client():
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
