import boto3
from langchain_aws import ChatBedrock
from core.config import settings
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import SystemMessage

# Import our custom tools
from agent.tools.redis_ops import (
    check_redis_health, 
    flush_stale_data,
    detect_noisy_neighbor,
    mitigate_noisy_neighbor,
    detect_cache_stampede,
    apply_jitter_or_lock,
    get_cluster_nodes
)

def setup_sre_agent():
    """Initializes the Agentic AI platform with Redis SRE tools using AWS Bedrock and LangGraph."""
    
    # Initialize the AWS Boto3 Client
    bedrock_client = boto3.client(
        service_name="bedrock-runtime",
        region_name=settings.aws_region
    )

    # Initialize the LLM (Native AWS Bedrock)
    llm = ChatBedrock(
        client=bedrock_client,
        model_id="anthropic.claude-3-haiku-20240307-v1:0",
        model_kwargs={"temperature": 0}
    )
    
    # Define the toolkit available to the agent
    tools = [
        check_redis_health,
        flush_stale_data,
        detect_noisy_neighbor,
        mitigate_noisy_neighbor,
        detect_cache_stampede,
        apply_jitter_or_lock,
        get_cluster_nodes
    ]
    
    # Define the system prompt
    system_message = SystemMessage(content=(
        "You are an expert Senior Site Reliability Engineer (SRE) specializing in Distributed Redis Clusters on AWS ECS Fargate. "
        "You manage a 6-node (3-Master/3-Replica) production cluster with EFS persistence. "
        "You have autonomous authority to diagnose sharding imbalances, mitigate noisy neighbors, and prevent cache stampedes. "
        "Always start by auditing the cluster state using get_cluster_nodes or check_redis_health if an issue is reported."
    ))
    
    # Initialize a tool-calling agent using LangGraph
    agent = create_react_agent(
        model=llm,
        tools=tools,
        prompt=system_message
    )
    
    return agent
