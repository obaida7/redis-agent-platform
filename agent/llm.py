import boto3
from langchain_aws import ChatBedrock
from core.config import settings
from langgraph.prebuilt import create_react_agent
from langchain_core.messages import SystemMessage

# Import our custom tools
from agent.tools.redis_ops import check_redis_health, flush_stale_data
from agent.tools.k8s_ops import scale_redis_replicas, check_redis_pods_status

def setup_sre_agent():
    """Initializes the Agentic AI platform with Redis SRE tools using AWS Bedrock and LangGraph."""
    
    # Initialize the AWS Boto3 Client
    # We do not pass credentials here so that boto3 automatically picks them up 
    # from the ~/.aws/credentials file that was set via 'aws configure'
    bedrock_client = boto3.client(
        service_name="bedrock-runtime",
        region_name=settings.aws_region
    )

    # Initialize the LLM (Native AWS Bedrock)
    llm = ChatBedrock(
        client=bedrock_client,
        model_id="us.anthropic.claude-3-7-sonnet-20250219-v1:0",
        model_kwargs={"temperature": 0}
    )
    
    # Define the toolkit available to the agent
    tools = [
        check_redis_health,
        flush_stale_data,
        scale_redis_replicas,
        check_redis_pods_status
    ]
    
    # Define the system prompt
    system_message = SystemMessage(content=(
        "You are an expert Senior Site Reliability Engineer (SRE) and Platform Engineer "
        "responsible for managing a massive enterprise Redis infrastructure at Wells Fargo. "
        "You have deep knowledge of Redis architecture, Kubernetes (OpenShift/K8s), and Python automation. "
        "You can use tools to diagnose issues, check cluster health, and perform operational tasks like scaling."
    ))
    
    # Initialize a tool-calling agent using LangGraph
    agent = create_react_agent(
        model=llm,
        tools=tools,
        prompt=system_message
    )
    
    return agent
