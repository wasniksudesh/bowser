"""
Configuration for LLM and Embedder services.
"""

# Providers
PROVIDER_OPENAI = "openai"
PROVIDER_ANTHROPIC = "anthropic"
PROVIDER_CLAUDE = "claude"
PROVIDER_GEMINI = "gemini"
PROVIDER_GOOGLE = "google"

# Models - OpenAI
MODEL_GPT4_TURBO = "gpt-4-turbo-preview"
MODEL_GPT3_TURBO = "gpt-3.5-turbo"
MODEL_GPT40_MINI = "gpt-4o-mini"
MODEL_TEXT_EMBEDDING_3_SMALL = "text-embedding-3-small"

# Models - Anthropic
MODEL_CLAUDE_3_5_SONNET = "claude-3-5-sonnet-20241022"

# Models - Gemini
MODEL_GEMINI_2_5_FLASH_LITE = "gemini-2.5-flash-lite"
MODEL_GEMINI_2_5_FLASH = "gemini-2.5-flash"
MODEL_GEMINI_3_0_FLASH = "gemini-3-flash-preview"
MODEL_TEXT_EMBEDDING_004 = "models/text-embedding-004"

# Defaults
DEFAULT_PROVIDER = PROVIDER_OPENAI
DEFAULT_MODEL_CLAUDE = MODEL_CLAUDE_3_5_SONNET
DEFAULT_MODEL_GEMINI = MODEL_GEMINI_3_0_FLASH
DEFAULT_MODEL_OPENAI = MODEL_GPT40_MINI

LLM_CONFIG = {
    "provider": "openai",   # gemini | openai | claude
    "model": DEFAULT_MODEL_OPENAI,
    "api_key": "OPENAI_KEY", # This will be replaced by actual env var name or value
    "temperature": 0
}

DEFAULT_EMBEDDER_GEMINI = MODEL_TEXT_EMBEDDING_004
DEFAULT_EMBEDDER_OPENAI = MODEL_TEXT_EMBEDDING_3_SMALL

EMBEDDER_CONFIG = {
    "provider": "openai",   # gemini | openai
    "model": DEFAULT_EMBEDDER_OPENAI,
    "api_key": "OPENAI_KEY"
}

VECTOR_STORE_PATH = "./data/"
