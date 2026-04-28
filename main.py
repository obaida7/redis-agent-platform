from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from agent.llm import setup_sre_agent

app = FastAPI(
    title="Redis Platform Engineering Agent API",
    description="An AI-powered agent platform for managing Redis Enterprise infrastructure.",
    version="1.0.0"
)

# Initialize the Langchain agent globally
sre_agent = setup_sre_agent()

class ChatRequest(BaseModel):
    message: str

class ChatResponse(BaseModel):
    response: str

from langchain_core.messages import HumanMessage

@app.post("/api/v1/chat", response_model=ChatResponse)
async def chat_with_agent(request: ChatRequest):
    """
    Endpoint to interact with the SRE Agent.
    The agent will parse the natural language message, decide which tools to use 
    (e.g., checking K8s pods or Redis health), execute them, and return a response.
    """
    try:
        # Run the agent synchronously using LangGraph
        result = sre_agent.invoke({"messages": [HumanMessage(content=request.message)]})
        
        # The output is the last message in the state
        return ChatResponse(response=result["messages"][-1].content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health_check():
    return {"status": "ok"}
