import json
from pathlib import Path
from typing import Dict, Optional
import re

class FrameworkDetector:
    """Detect frontend/backend frameworks and their requirements."""

    def detect_frontend_framework(self, project_path: str) -> Dict:
        """
        Detect frontend framework from package.json.

        Returns:
            {
                "framework": "nextjs" | "vite" | "react" | "vue" | "unknown",
                "requires_build_time_env": bool,
                "env_var_prefix": str,  # e.g., "NEXT_PUBLIC_" or "VITE_"
            }
        """
        package_json_path = Path(project_path) / "frontend" / "package.json"

        if not package_json_path.exists():
            # Try alternative locations
            package_json_path = Path(project_path) / "package.json"
            
        if not package_json_path.exists():
            return {
                "framework": "unknown",
                "requires_build_time_env": False,
                "env_var_prefix": "",
                "version": None
            }

        try:
            with open(package_json_path) as f:
                data = json.load(f)
                dependencies = {
                    **data.get("dependencies", {}),
                    **data.get("devDependencies", {})
                }

                # Check for Next.js
                if "next" in dependencies:
                    return {
                        "framework": "nextjs",
                        "requires_build_time_env": True,
                        "env_var_prefix": "NEXT_PUBLIC_",
                        "version": dependencies["next"]
                    }

                # Check for Vite
                if "vite" in dependencies:
                    return {
                        "framework": "vite",
                        "requires_build_time_env": True,
                        "env_var_prefix": "VITE_",
                        "version": dependencies.get("vite")
                    }

                # Check for Create React App
                if "react-scripts" in dependencies:
                    return {
                        "framework": "cra",
                        "requires_build_time_env": True,
                        "env_var_prefix": "REACT_APP_",
                        "version": dependencies.get("react-scripts")
                    }

                # Generic React
                if "react" in dependencies:
                    return {
                        "framework": "react",
                        "requires_build_time_env": False,
                        "env_var_prefix": "",
                        "version": dependencies.get("react")
                    }

                # Check for Vue
                if "vue" in dependencies:
                    return {
                        "framework": "vue",
                        "requires_build_time_env": False,
                        "env_var_prefix": "",
                        "version": dependencies.get("vue")
                    }

        except (json.JSONDecodeError, IOError) as e:
            print(f"Error reading package.json: {e}")

        return {
            "framework": "unknown",
            "requires_build_time_env": False,
            "env_var_prefix": "",
            "version": None
        }

    def detect_backend_api_prefix(self, project_path: str) -> str:
        """
        Detect if backend uses /api prefix by scanning code.

        Returns:
            "/api" or "" (empty string if no prefix)
        """
        backend_path = Path(project_path) / "backend"
        
        if not backend_path.exists():
            # Try alternative location
            backend_path = Path(project_path)

        # Check common backend entry files
        entry_files = [
            backend_path / "app" / "main.py",  # FastAPI
            backend_path / "main.py",
            backend_path / "server.js",  # Express
            backend_path / "app.js",
            backend_path / "index.js",
            backend_path / "src" / "index.js",
            backend_path / "src" / "app.js",
        ]

        for entry_file in entry_files:
            if entry_file.exists():
                try:
                    content = entry_file.read_text()

                    # FastAPI patterns
                    if 'prefix="/api"' in content or "prefix='/api'" in content:
                        return "/api"

                    # Express patterns
                    if "app.use('/api'" in content or 'app.use("/api"' in content:
                        return "/api"
                        
                    # Look for router includes with /api prefix
                    if re.search(r'app\.include_router\([^)]+prefix\s*=\s*["\']\/api["\']', content):
                        return "/api"
                        
                except IOError as e:
                    print(f"Error reading {entry_file}: {e}")

        return ""  # No API prefix detected

    def analyze_frontend_api_paths(self, project_path: str) -> bool:
        """
        Check if frontend code includes /api in API call paths.

        Returns:
            True if frontend includes "/api/" in paths
            False otherwise
        """
        frontend_path = Path(project_path) / "frontend" / "src"
        
        if not frontend_path.exists():
            # Try alternative locations
            frontend_path = Path(project_path) / "src"

        if not frontend_path.exists():
            return False

        # Common API client file locations
        api_files = [
            frontend_path / "lib" / "api.ts",
            frontend_path / "lib" / "api.js",
            frontend_path / "api.ts",
            frontend_path / "api.js",
            frontend_path / "services" / "api.ts",
            frontend_path / "services" / "api.js",
            frontend_path / "utils" / "api.ts",
            frontend_path / "utils" / "api.js",
            frontend_path / "api" / "index.ts",
            frontend_path / "api" / "index.js",
        ]

        for api_file in api_files:
            if api_file.exists():
                try:
                    content = api_file.read_text()

                    # Check for API calls with /api prefix
                    if '"/api/' in content or "'/api/" in content:
                        return True
                        
                    # Check for template literals with /api
                    if '`/api/' in content or '${' in content and '/api/' in content:
                        return True
                        
                except IOError as e:
                    print(f"Error reading {api_file}: {e}")

        return False

    def extract_env_vars_from_example(self, project_path: str) -> list:
        """
        Extract environment variable names from backend/.env.example file.
        
        Returns:
            List of environment variable names
        """
        env_example_path = Path(project_path) / "backend" / ".env.example"
        
        if not env_example_path.exists():
            # Try alternative locations
            env_example_path = Path(project_path) / ".env.example"
            
        if not env_example_path.exists():
            return []
            
        env_vars = []
        try:
            with open(env_example_path) as f:
                for line in f:
                    line = line.strip()
                    # Skip comments and empty lines
                    if line and not line.startswith('#'):
                        # Extract variable name (before = sign)
                        if '=' in line:
                            var_name = line.split('=')[0].strip()
                            if var_name:
                                env_vars.append(var_name)
        except IOError as e:
            print(f"Error reading .env.example: {e}")
            
        return env_vars

    def detect_ssl_on_server(self, target_ip: str, ssh_key_path: str) -> str:
        """
        Detect if SSL is configured on the target server.
        
        Returns:
            "https" if SSL certificates found, "http" otherwise
        """
        import subprocess
        
        try:
            result = subprocess.run(
                ["ssh", "-i", ssh_key_path, "-o", "StrictHostKeyChecking=no", 
                 "-o", "ConnectTimeout=10", f"ubuntu@{target_ip}",
                 "[ -d /etc/letsencrypt/live ] && ls /etc/letsencrypt/live/ 2>/dev/null | head -1 || echo ''"],
                capture_output=True,
                text=True,
                timeout=15
            )
            
            # If we found any certificate directory, SSL is configured
            if result.stdout.strip():
                return "https"
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, Exception) as e:
            print(f"Could not detect SSL configuration: {e}")
            
        return "http"  # Default to HTTP if can't detect
