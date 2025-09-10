from flask import Flask, request, render_template, redirect, url_for, session, jsonify, make_response
from authlib.integrations.flask_client import OAuth
import os
import requests
import json
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


def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)

    return decorated_function


def require_admin(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('login'))

        user_groups = session.get('user', {}).get('groups', [])
        if 'admin' not in user_groups:
            return "Access Denied: Admin role required", 403
        return f(*args, **kwargs)

    return decorated_function


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


@app.route('/login')
def login():
    # Get redirect parameter for post-login redirect
    redirect_param = request.args.get('redirect', '/')
    session['redirect_after_login'] = redirect_param

    redirect_uri = url_for('callback', _external=True)
    return keycloak.authorize_redirect(redirect_uri)


@app.route('/callback')
def callback():
    try:
        token = keycloak.authorize_access_token()
        user_info = token.get('userinfo')

        # Get user groups from token
        access_token = token.get('access_token')
        groups = []
        if access_token:
            # Decode JWT to get groups (in production, use proper JWT validation)
            try:
                decoded = jwt.decode(access_token, options={"verify_signature": False})
                groups = decoded.get('groups', [])
                # Also check for realm_access roles
                if 'realm_access' in decoded:
                    realm_roles = decoded['realm_access'].get('roles', [])
                    groups.extend(realm_roles)
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

        # Redirect to original destination
        redirect_url = session.pop('redirect_after_login', '/')
        return redirect(redirect_url)

    except Exception as e:
        logger.error(f"Login callback failed: {e}")
        return f"Login failed: {str(e)}", 400


@app.route('/logout')
def logout():
    # Clear session
    session.clear()

    # Build Keycloak logout URL
    logout_url = f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}/protocol/openid-connect/logout"
    post_logout_redirect = url_for('index', _external=True)

    return redirect(f"{logout_url}?post_logout_redirect_uri={post_logout_redirect}")


@app.route('/admin')
@require_admin
def admin():
    return render_template('admin.html', user=session['user'])


@app.route('/profile')
@require_auth
def profile():
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
        logger.info(f"Auth verification failed: No user in session")
        return '', 401

    user = session['user']
    user_groups = user.get('groups', [])

    logger.info(
        f"Auth verification for user: {user.get('username')}, groups: {user_groups}, required_role: {required_role}")

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

    logger.info(f"Auth verification successful for user: {user.get('username')}")
    return resp


@app.route('/health')
def health():
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'service': 'webapp',
        'keycloak_url': KEYCLOAK_URL,
        'realm': KEYCLOAK_REALM
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
            'keycloak_configured': bool(KEYCLOAK_URL and KEYCLOAK_REALM)
        }, 200
    except Exception as e:
        return {'error': str(e)}, 500


# Error handlers
@app.errorhandler(401)
def unauthorized(error):
    """Handle unauthorized access"""
    if request.path.startswith('/auth/verify'):
        # For auth_request calls, just return 401
        return '', 401
    else:
        # For regular requests, redirect to login
        return redirect(url_for('login', redirect=request.path))


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


if __name__ == '__main__':
    debug_mode = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    port = int(os.environ.get('WEBAPP_PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=debug_mode)