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


def validate_uploaded_audio(file):
    """
    Validate uploaded audio file (fond sonore d'escape).
    Vérifie taille, format et durée minimale (boucle trop courte = répétitive).
    Returns (is_valid, error_message, mime_type, extension)
    """
    import os

    MAX_FILE_SIZE = 20 * 1024 * 1024  # 20MB
    MIN_DURATION_SECONDS = 60

    if file.size > MAX_FILE_SIZE:
        return (False, "Fichier trop volumineux (max 20MB)", None, None)

    ALLOWED_MIME_TYPES = {
        'audio/mpeg': '.mp3',
        'audio/mp4': '.m4a',
        'audio/x-m4a': '.m4a',
        'audio/aac': '.aac',
    }
    ALLOWED_EXTENSIONS = {'.mp3', '.m4a', '.aac'}

    try:
        import magic
        file_mime = magic.from_buffer(file.read(4096), mime=True)
        file.seek(0)
    except ImportError:
        file_mime = None

    name_ext = os.path.splitext(file.name)[1].lower()
    ext = ALLOWED_MIME_TYPES.get(file_mime) or (name_ext if name_ext in ALLOWED_EXTENSIONS else None)
    if not ext:
        return (False, f"Type de fichier non autorisé: {file_mime or name_ext}", file_mime, None)

    # Durée minimale (nécessite mutagen ; sans lui, on ne peut pas la vérifier).
    # Classes explicites par extension plutôt que l'auto-détection générique
    # mutagen.File(), qui échoue silencieusement sur un fichier en mémoire
    # (InMemoryUploadedFile) sans nom de fichier réel sur disque.
    duration = None
    try:
        file.seek(0)
        if ext == '.mp3':
            from mutagen.mp3 import MP3
            audio = MP3(file)
        elif ext == '.m4a':
            from mutagen.mp4 import MP4
            audio = MP4(file)
        elif ext == '.aac':
            from mutagen.aac import AAC
            audio = AAC(file)
        else:
            audio = None
        file.seek(0)
        duration = audio.info.length if audio is not None and audio.info else None
    except Exception:
        duration = None

    if duration is None:
        return (False, "Impossible de lire la durée du fichier audio.", file_mime, ext)
    if duration < MIN_DURATION_SECONDS:
        return (
            False,
            f"Le fond sonore doit durer au moins {MIN_DURATION_SECONDS} secondes "
            f"(durée détectée : {int(duration)}s).",
            file_mime,
            ext,
        )

    return (True, None, file_mime or "audio/*", ext)
