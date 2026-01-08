# games/file_upload_secure.py
"""Secure file upload validation for CityScape"""

def validate_uploaded_image(file):
    """
    Validate uploaded image file
    Returns (is_valid, error_message, mime_type, extension)
    """
    try:
        import magic
    except ImportError:
        # Fallback si python-magic n'est pas installé
        return validate_by_extension(file)

    # Vérification de la taille (max 5MB)
    MAX_FILE_SIZE = 5 * 1024 * 1024
    if file.size > MAX_FILE_SIZE:
        return (False, "Fichier trop volumineux (max 5MB)", None, None)

    # Vérification du type MIME réel
    ALLOWED_MIME_TYPES = {
        'image/jpeg': '.jpg',
        'image/png': '.png',
        'image/gif': '.gif',
        'image/webp': '.webp'
    }

    file_mime = magic.from_buffer(file.read(2048), mime=True)
    file.seek(0)  # Reset le pointeur du fichier

    if file_mime not in ALLOWED_MIME_TYPES:
        return (False, f"Type de fichier non autorisé: {file_mime}", file_mime, None)

    ext = ALLOWED_MIME_TYPES[file_mime]
    return (True, None, file_mime, ext)


def validate_by_extension(file):
    """
    Fallback validation by extension only (less secure)
    """
    import os

    MAX_FILE_SIZE = 5 * 1024 * 1024
    if file.size > MAX_FILE_SIZE:
        return (False, "Fichier trop volumineux (max 5MB)", None, None)

    allowed_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'}
    ext = os.path.splitext(file.name)[1].lower()

    if ext not in allowed_extensions:
        return (False, f"Extension non autorisée: {ext}", None, ext)

    return (True, None, "image/*", ext)
