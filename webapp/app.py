from flask import Flask, request, render_template, redirect, url_for, session, jsonify, make_response
from authlib.integrations.flask_client import OAuth
import os
import requests
import json
import time
from functools import wraps
from urllib.parse import urlencode
import jwt
import logging

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'your-secret-key-change-this')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Keycloak configuration
KEYCLOAK_URL = os.environ.get('KEYCLOAK_URL', 'http://keycloak:8080/auth')
KEYCLOAK_REALM = os.environ.get('KEYCLOAK_REALM', 'master')
KEYCLOAK_CLIENT_ID = os.environ.get('KEYCLOAK_CLIENT_ID', 'webapp')
KEYCLOAK_CLIENT_SECRET = os.environ.get('KEYCLOAK_CLIENT_SECRET', 'webapp-secret')

# Wiki.js configuration
WIKIJS_URL = os.environ.get('WIKIJS_URL', f"https://{os.environ.get('DOMAIN', 'rancher.local')}/wiki")
WIKIJS_ENABLED = os.environ.get('WIKIJS_ENABLED', 'true').lower() == 'true'
DOCUMENTATION_URL = os.environ.get('DOCUMENTATION_URL', WIKIJS_URL)

# OAuth setup
oauth = OAuth(app)
keycloak = oauth.register(
    name='keycloak',
    client_id=KEYCLOAK_CLIENT_ID,
    client_secret=KEYCLOAK_CLIENT_SECRET,
    server_metadata_url=f'{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/.well-known/openid-configuration',
    client_kwargs={
        'scope': 'openid email profile roles'
    }
)


# Rate limiting class for security
class RateLimiter:
    def __init__(self):
        self.attempts = {}
        self.lockouts = {}

    def is_rate_limited(self, username, max_attempts=5, window=300, lockout_duration=900):
        """Check if username is rate limited (5 attempts per 5 minutes, 15 min lockout)"""
        now = time.time()
        username = username.lower()  # Case insensitive

        # Check if user is in lockout period
        if username in self.lockouts:
            if now - self.lockouts[username] < lockout_duration:
                return True
            else:
                # Lockout period expired, remove from lockouts
                del self.lockouts[username]

        # Initialize attempts list if not exists
        if username not in self.attempts:
            self.attempts[username] = []

        # Remove old attempts outside the window
        self.attempts[username] = [t for t in self.attempts[username] if now - t < window]

        # Check if too many attempts
        if len(self.attempts[username]) >= max_attempts:
            # Add to lockouts
            self.lockouts[username] = now
            logger.warning(f"User {username} locked out due to too many failed attempts")
            return True

        return False

    def record_attempt(self, username):
        """Record a failed login attempt"""
        now = time.time()
        username = username.lower()

        if username not in self.attempts:
            self.attempts[username] = []

        self.attempts[username].append(now)

    def clear_attempts(self, username):
        """Clear attempts on successful login"""
        username = username.lower()
        if username in self.attempts:
            del self.attempts[username]
        if username in self.lockouts:
            del self.lockouts[username]


# Initialize rate limiter
rate_limiter = RateLimiter()


def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('index'))
        return f(*args, **kwargs)

    return decorated_function


def require_admin(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('index'))

        user_groups = session.get('user', {}).get('groups', [])
        if 'admin' not in user_groups:
            return "Access Denied: Admin role required", 403
        return f(*args, **kwargs)

    return decorated_function


# Add template context processor to make Wiki.js variables available in all templates
@app.context_processor
def inject_wikijs_config():
    return {
        'wikijs_url': WIKIJS_URL,
        'wikijs_enabled': WIKIJS_ENABLED,
        'documentation_url': DOCUMENTATION_URL
    }


@app.route('/')
def index():
    if 'user' in session:
        # User is logged in, redirect to monitoring page
        return redirect(url_for('monitoring'))
    else:
        # Show login page
        return render_template('login.html')


@app.route('/monitoring')
@require_auth
def monitoring():
    """Main monitoring dashboard page"""
    return render_template('monitoring.html', user=session['user'])


@app.route('/documentation')
@require_auth
def documentation():
    """Redirect to Wiki.js documentation"""
    if WIKIJS_ENABLED:
        return redirect(DOCUMENTATION_URL)
    else:
        return render_template('error.html',
                             error_code=503,
                             error_message="Documentation service is not available"), 503


@app.route('/login')
def login():
    """SSO redirect login (original OAuth method)"""
    redirect_param = request.args.get('redirect', '/')
    session['redirect_after_login'] = redirect_param

    redirect_uri = url_for('callback', _external=True)
    return keycloak.authorize_redirect(redirect_uri)


@app.route('/direct-login', methods=['POST'])
def direct_login():
    """Handle direct username/password login"""
    username = request.form.get('username', '').strip()
    password = request.form.get('password', '')

    # Basic validation
    if not username or not password:
        return render_template('login.html', error="Username and password are required")

    # Rate limiting check
    if rate_limiter.is_rate_limited(username):
        logger.warning(f"Rate limit exceeded for user: {username}")
        return render_template('login.html',
                               error="Too many failed attempts. Account temporarily locked. Please try again later.")

    try:
        # Direct authentication with Keycloak using password grant
        token_url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"

        token_data = {
            'grant_type': 'password',
            'client_id': KEYCLOAK_CLIENT_ID,
            'client_secret': KEYCLOAK_CLIENT_SECRET,
            'username': username,
            'password': password,
            'scope': 'openid profile email roles'
        }

        logger.info(f"Attempting direct login for user: {username}")

        # Request tokens from Keycloak
        response = requests.post(token_url, data=token_data, timeout=10)

        if response.status_code == 200:
            tokens = response.json()
            access_token = tokens.get('access_token')

            if access_token:
                # Get user info from Keycloak
                userinfo_url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/userinfo"
                headers = {'Authorization': f'Bearer {access_token}'}

                userinfo_response = requests.get(userinfo_url, headers=headers, timeout=10)

                if userinfo_response.status_code == 200:
                    user_info = userinfo_response.json()

                    # Decode JWT to get groups and roles
                    groups = []
                    try:
                        decoded = jwt.decode(access_token, options={"verify_signature": False})
                        groups = decoded.get('groups', [])
                        # Also check for realm_access roles
                        if 'realm_access' in decoded:
                            realm_roles = decoded['realm_access'].get('roles', [])
                            groups.extend(realm_roles)
                        # Check for resource_access roles
                        if 'resource_access' in decoded and KEYCLOAK_CLIENT_ID in decoded['resource_access']:
                            client_roles = decoded['resource_access'][KEYCLOAK_CLIENT_ID].get('roles', [])
                            groups.extend(client_roles)
                    except Exception as e:
                        logger.error(f"Error decoding JWT: {e}")

                    # Store user session
                    session['user'] = {
                        'id': user_info.get('sub'),
                        'username': user_info.get('preferred_username'),
                        'email': user_info.get('email'),
                        'name': user_info.get('name'),
                        'groups': list(set(groups))  # Remove duplicates
                    }

                    # Store tokens for auth verification
                    session['access_token'] = access_token
                    session['refresh_token'] = tokens.get('refresh_token')
                    session['token_expires'] = time.time() + tokens.get('expires_in', 300)

                    # Clear rate limiting on successful login
                    rate_limiter.clear_attempts(username)

                    logger.info(f"Direct login successful for user: {username}")

                    # Redirect to monitoring dashboard
                    redirect_url = request.args.get('redirect', '/monitoring')
                    return redirect(redirect_url)
                else:
                    logger.error(f"Failed to get user info: {userinfo_response.status_code}")
                    rate_limiter.record_attempt(username)
                    return render_template('login.html', error="Failed to retrieve user information")
            else:
                logger.error("No access token received")
                rate_limiter.record_attempt(username)
                return render_template('login.html', error="Authentication failed")
        else:
            # Handle authentication errors
            error_data = response.json() if response.headers.get('content-type', '').startswith(
                'application/json') else {}
            error_description = error_data.get('error_description', 'Invalid username or password')

            # Record failed attempt
            rate_limiter.record_attempt(username)

            logger.warning(f"Direct login failed for user {username}: {error_description}")

            # Don't expose detailed error messages for security
            if response.status_code == 401:
                return render_template('login.html', error="Invalid username or password")
            else:
                return render_template('login.html', error="Authentication failed. Please try again.")

    except requests.exceptions.Timeout:
        logger.error("Timeout connecting to Keycloak")
        return render_template('login.html', error="Authentication service timeout. Please try again.")
    except requests.exceptions.ConnectionError:
        logger.error("Connection error to Keycloak")
        return render_template('login.html', error="Cannot connect to authentication service")
    except Exception as e:
        logger.error(f"Direct login error: {str(e)}")
        return render_template('login.html', error="Login failed. Please try again.")


@app.route('/callback')
def callback():
    """Handle SSO callback (original OAuth flow)"""
    try:
        token = keycloak.authorize_access_token()
        user_info = token.get('userinfo')

        # Get user groups from token
        access_token = token.get('access_token')
        groups = []
        if access_token:
            try:
                decoded = jwt.decode(access_token, options={"verify_signature": False})
                groups = decoded.get('groups', [])
                # Also check for realm_access roles
                if 'realm_access' in decoded:
                    realm_roles = decoded['realm_access'].get('roles', [])
                    groups.extend(realm_roles)
                # Check for resource_access roles
                if 'resource_access' in decoded and KEYCLOAK_CLIENT_ID in decoded['resource_access']:
                    client_roles = decoded['resource_access'][KEYCLOAK_CLIENT_ID].get('roles', [])
                    groups.extend(client_roles)
            except Exception as e:
                logger.error(f"Error decoding JWT: {e}")

        session['user'] = {
            'id': user_info.get('sub'),
            'username': user_info.get('preferred_username'),
            'email': user_info.get('email'),
            'name': user_info.get('name'),
            'groups': list(set(groups))  # Remove duplicates
        }

        # Store token for auth verification
        session['access_token'] = access_token
        session['token_expires'] = time.time() + token.get('expires_in', 300)

        logger.info(f"SSO login successful for user: {user_info.get('preferred_username')}")

        # Redirect to original destination
        redirect_url = session.pop('redirect_after_login', '/monitoring')
        return redirect(redirect_url)

    except Exception as e:
        logger.error(f"SSO callback failed: {e}")
        return render_template('login.html', error=f"SSO login failed: {str(e)}")


@app.route('/logout')
def logout():
    """Handle user logout - simple session clear"""
    username = session.get('user', {}).get('username', 'unknown')

    # Clear session completely
    session.clear()

    logger.info(f"User logged out: {username}")

    # Show logged out page instead of redirecting to Keycloak
    return render_template('logout.html')


@app.route('/admin')
@require_admin
def admin():
    """Admin portal page"""
    return render_template('admin.html', user=session['user'])


@app.route('/profile')
@require_auth
def profile():
    """User profile page"""
    return render_template('profile.html', user=session['user'])


# Auth verification endpoint for nginx auth_request
@app.route('/auth/verify')
def auth_verify():
    """
    This endpoint is called by nginx auth_request to verify authentication.
    It checks session-based auth and returns appropriate headers.
    """
    required_role = request.args.get('role', None)

    # Check if user is authenticated via session
    if 'user' not in session:
        logger.debug(f"Auth verification failed: No user in session")
        return '', 401

    user = session['user']
    user_groups = user.get('groups', [])

    logger.debug(
        f"Auth verification for user: {user.get('username')}, groups: {user_groups}, required_role: {required_role}")

    # Check token expiration
    token_expires = session.get('token_expires', 0)
    if token_expires > 0 and time.time() > token_expires:
        logger.info(f"Token expired for user: {user.get('username')}")
        session.clear()
        return '', 401

    # Check role requirements
    if required_role:
        if required_role == 'admin' and 'admin' not in user_groups:
            logger.info(f"Auth verification failed: Admin role required but user has: {user_groups}")
            return '', 403
        elif required_role in ['view', 'modify'] and not any(
                group in user_groups for group in [required_role, 'admin']):
            logger.info(f"Auth verification failed: Role {required_role} required but user has: {user_groups}")
            return '', 403
    else:
        # General auth check - must have at least view access or be authenticated
        if not user_groups and 'user' not in session:
            logger.info(f"Auth verification failed: No valid groups and not authenticated")
            return '', 403

    # Set headers for nginx
    resp = make_response('', 200)
    resp.headers['X-Forwarded-User'] = user.get('username', '')
    resp.headers['X-Forwarded-Groups'] = ','.join(user_groups)
    resp.headers['X-User-Email'] = user.get('email', '')
    resp.headers['X-User-Name'] = user.get('name', '')

    logger.debug(f"Auth verification successful for user: {user.get('username')}")
    return resp


@app.route('/health')
def health():
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'service': 'webapp',
        'keycloak_url': KEYCLOAK_URL,
        'realm': KEYCLOAK_REALM,
        'wikijs_enabled': WIKIJS_ENABLED,
        'wikijs_url': WIKIJS_URL if WIKIJS_ENABLED else None,
        'version': '1.0.0'
    }, 200


@app.route('/nginx-status')
def nginx_status():
    """Status endpoint for nginx to check webapp health"""
    try:
        # Quick health check
        if 'user' in session:
            user_status = f"authenticated as {session['user'].get('username')}"
        else:
            user_status = "not authenticated"

        return {
            'webapp': 'running',
            'session': user_status,
            'keycloak_configured': bool(KEYCLOAK_URL and KEYCLOAK_REALM),
            'wikijs_enabled': WIKIJS_ENABLED
        }, 200
    except Exception as e:
        return {'error': str(e)}, 500


@app.route('/refresh-token', methods=['POST'])
def refresh_token():
    """Refresh access token using refresh token"""
    if 'refresh_token' not in session:
        return jsonify({'error': 'No refresh token available'}), 401

    try:
        token_url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"

        token_data = {
            'grant_type': 'refresh_token',
            'client_id': KEYCLOAK_CLIENT_ID,
            'client_secret': KEYCLOAK_CLIENT_SECRET,
            'refresh_token': session['refresh_token']
        }

        response = requests.post(token_url, data=token_data, timeout=10)

        if response.status_code == 200:
            tokens = response.json()
            session['access_token'] = tokens.get('access_token')
            session['refresh_token'] = tokens.get('refresh_token')
            session['token_expires'] = time.time() + tokens.get('expires_in', 300)

            return jsonify({'status': 'success'}), 200
        else:
            # Refresh failed, clear session
            session.clear()
            return jsonify({'error': 'Token refresh failed'}), 401

    except Exception as e:
        logger.error(f"Token refresh error: {e}")
        return jsonify({'error': 'Token refresh failed'}), 500


# Error handlers
@app.errorhandler(401)
def unauthorized(error):
    """Handle unauthorized access"""
    if request.path.startswith('/auth/verify'):
        # For auth_request calls, just return 401
        return '', 401
    else:
        # For regular requests, redirect to login
        return redirect(url_for('index'))


@app.errorhandler(403)
def forbidden(error):
    """Handle forbidden access"""
    if request.path.startswith('/auth/verify'):
        # For auth_request calls, just return 403
        return '', 403
    else:
        # For regular requests, show error page
        return render_template('error.html',
                               error_code=403,
                               error_message="Access Denied: Insufficient permissions"), 403


@app.errorhandler(404)
def not_found(error):
    """Handle not found errors"""
    return render_template('error.html',
                           error_code=404,
                           error_message="Page not found"), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle internal server errors"""
    logger.error(f"Internal server error: {error}")
    return render_template('error.html',
                           error_code=500,
                           error_message="Internal server error"), 500


# Session configuration for security
@app.before_request
def before_request():
    """Configure session security before each request"""
    session.permanent = True
    app.permanent_session_lifetime = 3600  # 1 hour session timeout

    # Ensure secure session cookies in production
    if not app.debug:
        session.cookie_secure = True
        session.cookie_httponly = True
        session.cookie_samesite = 'Lax'


# Application startup
if __name__ == '__main__':
    debug_mode = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    port = int(os.environ.get('WEBAPP_PORT', 8000))

    logger.info(f"Starting webapp on port {port}")
    logger.info(f"Keycloak URL: {KEYCLOAK_URL}")
    logger.info(f"Keycloak Realm: {KEYCLOAK_REALM}")
    logger.info(f"Wiki.js URL: {WIKIJS_URL}")
    logger.info(f"Wiki.js Enabled: {WIKIJS_ENABLED}")
    logger.info(f"Debug mode: {debug_mode}")

    app.run(host='0.0.0.0', port=port, debug=debug_mode)