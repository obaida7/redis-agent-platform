from pydantic_settings import BaseSettings

from typing import Optional

class Settings(BaseSettings):
    redis_host: str = "localhost"
    redis_port: int = 12000
    redis_password: str = ""
    redis_cluster_mode: bool = False
    aws_region: str = "us-east-1"
    aws_access_key_id: Optional[str] = None
    aws_secret_access_key: Optional[str] = None
    k8s_namespace: str = "redis"
    cluster_name: str = "redis-enterprise"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
