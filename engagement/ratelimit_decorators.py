# engagement/ratelimit_decorators.py
"""Rate limiting decorators for CityScape API endpoints"""

from django_ratelimit.decorators import ratelimit
from django.utils.decorators import method_decorator

# Rate limits for authentication endpoints
auth_rate_limit = method_decorator(ratelimit(key='ip', rate='5/h', method='POST', block=True), name='post')
password_reset_rate_limit = method_decorator(ratelimit(key='ip', rate='3/h', method='POST', block=True), name='post')
google_signin_rate_limit = method_decorator(ratelimit(key='ip', rate='10/h', method='POST', block=True), name='post')
email_verify_rate_limit = method_decorator(ratelimit(key='ip', rate='5/h', method='POST', block=True), name='post')

# Rate limits for game actions
answer_submit_rate_limit = method_decorator(ratelimit(key='user', rate='30/m', method='POST', block=True), name='post')
