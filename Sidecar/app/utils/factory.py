from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_google_genai import ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings
from langchain_anthropic import ChatAnthropic
import os
import logging

logger = logging.getLogger(__name__)

def get_llm(provider: str, model: str, api_key: str, temperature: float = 0):
    """Factory function to get LLM instance."""
    actual_api_key = api_key
    if api_key.isupper() or not api_key:
         actual_api_key = os.getenv(api_key) or api_key

    p = provider.lower()

    if p == "gemini":
        return ChatGoogleGenerativeAI(
            model=model,
            google_api_key=actual_api_key,
            temperature=temperature
        )

    if p == "openai":
        return ChatOpenAI(
            model=model,
            api_key=actual_api_key,
            temperature=temperature
        )

    if p in ["claude", "anthropic"]:
        return ChatAnthropic(
            model=model,
            anthropic_api_key=actual_api_key,
            temperature=temperature
        )

    raise ValueError(f"Unsupported LLM provider: {provider}")


def get_embedder(provider: str, model: str, api_key: str):
    """Factory function to get embedder instance."""
    actual_api_key = api_key
    if api_key.isupper() or not api_key:
         actual_api_key = os.getenv(api_key) or api_key

    p = provider.lower()

    if p == "gemini":
        return GoogleGenerativeAIEmbeddings(
            model=model,
            google_api_key=actual_api_key
        )

    if p == "openai":
        return OpenAIEmbeddings(
            model=model,
            api_key=actual_api_key
        )

    raise ValueError(f"Unsupported embedder provider: {provider}")
