"""
V1 Plugins for Agent Mode
Auto-discovers all plugins in this directory
"""

import os
import importlib
import inspect
from typing import List, Callable
from app.models.agent_schemas import Plugin


def discover_plugins() -> List[Callable[[], Plugin]]:
    """
    Automatically discover all plugin getter functions in the plugins directory.
    Looks for functions matching the pattern get_*_plugin() that return Plugin objects.
    
    Returns:
        List of plugin getter functions
    """
    plugin_getters = []
    current_dir = os.path.dirname(__file__)

    for filename in os.listdir(current_dir):
        filepath = os.path.join(current_dir, filename)

        if os.path.isdir(filepath):
            # Sub-package plugin (e.g. gmail_plugin/)
            if filename.startswith('_'):
                continue
            init_file = os.path.join(filepath, '__init__.py')
            if not os.path.exists(init_file):
                continue
            try:
                module = importlib.import_module(f'.{filename}', package='app.services.plugins')
                for name, obj in inspect.getmembers(module, inspect.isfunction):
                    if name.startswith('get_') and name.endswith('_plugin'):
                        plugin_getters.append(obj)
            except Exception as e:
                print(f"Warning: Failed to import plugin package {filename}: {e}")

        elif filename.endswith('.py') and filename != '__init__.py' and not filename.startswith('_'):
            # Single-file plugin (e.g. hackernews_plugin.py)
            module_name = filename[:-3]
            try:
                module = importlib.import_module(f'.{module_name}', package='app.services.plugins')
                for name, obj in inspect.getmembers(module, inspect.isfunction):
                    if name.startswith('get_') and name.endswith('_plugin'):
                        plugin_getters.append(obj)
            except Exception as e:
                print(f"Warning: Failed to import plugin module {module_name}: {e}")

    return plugin_getters


# Auto-discover all plugins
_plugin_getters = discover_plugins()

# Export for backward compatibility
from .github_plugin import get_github_plugin
from .http_plugin import get_http_plugin
from .text_analysis_plugin import get_text_analysis_plugin
from .gmail_plugin import get_gmail_plugin
from .hackernews_plugin import get_hackernews_plugin

__all__ = [
    'discover_plugins',
    'get_github_plugin',
    'get_http_plugin',
    'get_text_analysis_plugin',
    'get_gmail_plugin',
    'get_hackernews_plugin',
]
