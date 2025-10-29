from django.contrib.auth import get_user_model
from games.models import EscapeGame
User = get_user_model()

EG_ID = 16          # <- ID de l'escape à réassigner
NEW_USER_ID = 2     # <- OU mets None et utilise NEW_USERNAME ci-dessous
NEW_USERNAME = None # <- e.g. "bob_test"

eg = EscapeGame.objects.get(pk=EG_ID)
if NEW_USER_ID is not None:
    u = User.objects.get(pk=NEW_USER_ID)
elif NEW_USERNAME:
    u = User.objects.get(username=NEW_USERNAME)
else:
    raise ValueError("Fournis NEW_USER_ID ou NEW_USERNAME")

# Selon ton modèle (owner OU created_by)
if hasattr(eg, "owner"):
    eg.owner = u
    eg.save(update_fields=["owner"])
elif hasattr(eg, "created_by"):
    eg.created_by = u
    eg.save(update_fields=["created_by"])
else:
    raise AttributeError("Ni 'owner' ni 'created_by' sur EscapeGame")

print(f"OK: escape #{eg.id} -> user={u.id} ({u.username})")
