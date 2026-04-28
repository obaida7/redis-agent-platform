from kubernetes import client, config
from langchain.tools import tool
from core.config import settings

def get_k8s_client():
    try:
        config.load_kube_config()
    except Exception:
        config.load_incluster_config()
    return client.CustomObjectsApi(), client.CoreV1Api()

@tool
def scale_redis_replicas(nodes: int) -> str:
    """Scales the Redis Enterprise Cluster to the specified number of nodes. Valid inputs are 3, 5, 7, etc. (odd numbers)."""
    try:
        crd_api, _ = get_k8s_client()
        
        # We patch the RedisEnterpriseCluster custom resource
        body = {"spec": {"nodes": nodes}}
        
        crd_api.patch_namespaced_custom_object(
            group="app.redislabs.com",
            version="v1alpha1",
            namespace=settings.k8s_namespace,
            plural="redisenterpriseclusters",
            name=settings.cluster_name,
            body=body
        )
        return f"Successfully issued patch to scale Redis Enterprise Cluster '{settings.cluster_name}' to {nodes} nodes."
    except Exception as e:
        return f"Failed to scale Redis cluster: {str(e)}"

@tool
def check_redis_pods_status() -> str:
    """Checks the Kubernetes status of all pods belonging to the Redis Enterprise cluster."""
    try:
        _, core_api = get_k8s_client()
        pods = core_api.list_namespaced_pod(
            namespace=settings.k8s_namespace,
            label_selector="app=redis-enterprise"
        )
        
        status_lines = []
        for pod in pods.items:
            status_lines.append(f"Pod {pod.metadata.name}: {pod.status.phase}")
            
        if not status_lines:
            return "No Redis pods found in the cluster."
            
        return "Kubernetes Pod Statuses:\n" + "\n".join(status_lines)
    except Exception as e:
        return f"Failed to fetch pod status: {str(e)}"
