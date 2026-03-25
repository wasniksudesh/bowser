"""
macOS Notes App Management Tool

Provides functionality to create, save, list, and manage notes using Apple Notes via AppleScript.
"""

import logging
import subprocess
import json
from .base import BaseBrowserTool

logger = logging.getLogger(__name__)

class MacNotesTool(BaseBrowserTool):
    """
    Tool for managing notes using macOS Notes app.
    
    This tool allows the AI agent to create, save, list, and manage notes
    by scripting the Apple Notes application.
    """
    
    name = "Mac_Notes"
    description = (
        "Manage macOS Notes. Available commands:\n"
        "- create-note: Create a new note (format: 'create-note|title|content')\n"
        "- list-notes: List all notes (returns titles and modification dates)\n"
        "- show-note: Show content of a specific note by title (format: 'show-note|title')\n"
        "- search-notes: Search notes by query (format: 'search-notes|query')"
    )
    
    def run(self, input_str: str) -> str:
        """
        Execute the tool's functionality based on the command.
        
        Args:
            input_str: Command string with parameters separated by '|'.
            
        Returns:
            str: Result of the operation.
        """
        try:
            parts = input_str.split('|', 2)
            command = parts[0].strip().lower()
            
            if command == "create-note":
                if len(parts) < 3:
                    return "Error: create-note requires title and content (format: 'create-note|title|content')"
                title = parts[1].strip()
                content = parts[2]
                return self.create_note(title, content)
            
            elif command == "list-notes":
                return self.list_notes()
            
            elif command == "show-note":
                if len(parts) < 2:
                    return "Error: show-note requires title (format: 'show-note|title')"
                title = parts[1].strip()
                return self.get_note_content(title)

            elif command == "search-notes":
                if len(parts) < 2:
                    return "Error: search-notes requires query (format: 'search-notes|query')"
                query = parts[1].strip()
                return self.search_notes(query)
            
            else:
                return f"Error: Unknown command '{command}'. Available commands: create-note, list-notes, show-note, search-notes"
        
        except Exception as e:
            logger.error(f"Error executing Mac Notes tool: {e}", exc_info=True)
            return f"Error: {str(e)}"
    
    def create_note(self, title: str, content: str) -> str:
        """
        Create a new note in macOS Notes app.
        """
        # AppleScript to create a new note
        # We wrap content in simple HTML because Notes body is HTML
        escaped_content = self._escape_applescript(content).replace(r'\\n', '<br>')
        html_content = f"<h1>{self._escape_applescript(title)}</h1><p>{escaped_content}</p>"
        
        applescript = f'''
        tell application "Notes"
            tell default account
                tell folder "Notes"
                    make new note with properties {{name:"{self._escape_applescript(title)}", body:"{html_content}"}}
                end tell
            end tell
        end tell
        '''
        
        try:
            self._run_applescript(applescript)
            logger.info(f"Note created successfully: {title}")
            return f"Success: Note '{title}' created in macOS Notes."
        except Exception as e:
            # Fallback: try creating in the default location without specifying folder
            fallback_script = f'''
            tell application "Notes"
                make new note with properties {{name:"{self._escape_applescript(title)}", body:"{html_content}"}}
            end tell
            '''
            try:
                self._run_applescript(fallback_script)
                return f"Success: Note '{title}' created in macOS Notes (default folder)."
            except Exception as e2:
                logger.error(f"Error creating note: {e2}", exc_info=True)
                return f"Error creating note: {str(e2)}"

    def list_notes(self) -> str:
        """
        List all notes from the default account.
        """
        # This script gets name and modification date of all notes
        applescript = '''
        tell application "Notes"
            tell default account
                set noteList to {}
                repeat with aNote in notes
                    set noteInfo to {name of aNote, modification date of aNote as string}
                    copy noteInfo to end of noteList
                end repeat
                return noteList
            end tell
        end tell
        '''
        
        try:
            output = self._run_applescript(applescript)
            # Output format is "name1, date1, name2, date2, ..."
            # We need to parse this comma-separated list carefully or just return raw for now.
            # A cleaner way is to json stringify in applescript or just get names.
            
            # Let's simplify and just get names for reliability
            simple_script = '''
            tell application "Notes"
                tell default account
                    get name of every note
                end tell
            end tell
            '''
            names_raw = self._run_applescript(simple_script)
            if not names_raw:
                return "No notes found."
            
            names = [n.strip() for n in names_raw.split(', ')]
            return json.dumps({"total_notes": len(names), "notes": names}, indent=2)
            
        except Exception as e:
            logger.error(f"Error listing notes: {e}", exc_info=True)
            return f"Error listing notes: {str(e)}"

    def get_note_content(self, title: str) -> str:
        """
        Get the body of a note with the given title.
        """
        applescript = f'''
        tell application "Notes"
            tell default account
                try
                    get body of note "{self._escape_applescript(title)}"
                on error
                    return "NOTE_NOT_FOUND"
                end try
            end tell
        end tell
        '''
        
        try:
            content = self._run_applescript(applescript)
            if content.strip() == "NOTE_NOT_FOUND":
                return f"Error: Note with title '{title}' not found."
            
            # Clean up HTML if possible, or just return as is (LLM can handle HTML)
            return content
        except Exception as e:
            logger.error(f"Error getting note content: {e}", exc_info=True)
            return f"Error getting note content: {str(e)}"

    def search_notes(self, query: str) -> str:
        """
        Search for notes containing specific text.
        """
        applescript = f'''
        tell application "Notes"
            tell default account
                set matchingNotes to name of every note where body contains "{self._escape_applescript(query)}" or name contains "{self._escape_applescript(query)}"
            end tell
        end tell
        '''
        try:
            result = self._run_applescript(applescript)
            if not result:
                return "No matching notes found."
            return f"Found notes: {result}"
        except Exception as e:
            logger.error(f"Error searching notes: {e}", exc_info=True)
            return f"Error searching notes: {str(e)}"

    def _run_applescript(self, script: str) -> str:
        try:
            result = subprocess.run(
                ['osascript', '-e', script],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode != 0:
                raise Exception(result.stderr)
            return result.stdout.strip()
        except Exception as e:
            logger.error(f"AppleScript error: {e}")
            raise

    def _escape_applescript(self, text: str) -> str:
        return text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
