# Code à ajouter dans engagement/views.py après MeView (après la ligne 96)

class UserProfileView(APIView):
    """
    GET: Retourne le profil complet de l'utilisateur
    PATCH: Met à jour les informations du profil
    """
    authentication_classes = [TokenAuthentication]
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        u = request.user
        return Response({
            "id": u.id,
            "username": u.username,
            "email": u.email or "",
            "first_name": u.first_name or "",
            "last_name": u.last_name or "",
            "is_staff": u.is_staff,
            "is_superuser": u.is_superuser,
        })

    def patch(self, request):
        u = request.user
        data = request.data

        # Mise à jour des champs autorisés
        if 'username' in data:
            new_username = data['username'].strip()
            if not new_username:
                return Response(
                    {"detail": "Le nom d'utilisateur ne peut pas être vide"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            # Vérifier si le username existe déjà (sauf pour l'utilisateur actuel)
            if User.objects.filter(username=new_username).exclude(id=u.id).exists():
                return Response(
                    {"detail": "Ce nom d'utilisateur est déjà utilisé"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            u.username = new_username

        if 'email' in data:
            new_email = data['email'].strip()
            if new_email:
                # Validation basique de l'email
                if '@' not in new_email or '.' not in new_email:
                    return Response(
                        {"detail": "Adresse email invalide"},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                # Vérifier si l'email existe déjà (sauf pour l'utilisateur actuel)
                if User.objects.filter(email=new_email).exclude(id=u.id).exists():
                    return Response(
                        {"detail": "Cette adresse email est déjà utilisée"},
                        status=status.HTTP_400_BAD_REQUEST
                    )
            u.email = new_email

        if 'first_name' in data:
            u.first_name = data['first_name'].strip()

        if 'last_name' in data:
            u.last_name = data['last_name'].strip()

        u.save()

        return Response({
            "id": u.id,
            "username": u.username,
            "email": u.email or "",
            "first_name": u.first_name or "",
            "last_name": u.last_name or "",
        })


class ChangePasswordView(APIView):
    """
    POST: Change le mot de passe de l'utilisateur
    Requiert: old_password, new_password
    """
    authentication_classes = [TokenAuthentication]
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        u = request.user
        data = request.data

        old_password = data.get('old_password', '')
        new_password = data.get('new_password', '')

        if not old_password or not new_password:
            return Response(
                {"detail": "Les champs old_password et new_password sont requis"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Vérifier l'ancien mot de passe
        if not u.check_password(old_password):
            return Response(
                {"detail": "Le mot de passe actuel est incorrect"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Validation du nouveau mot de passe
        if len(new_password) < 8:
            return Response(
                {"detail": "Le nouveau mot de passe doit contenir au moins 8 caractères"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Changer le mot de passe
        u.set_password(new_password)
        u.save()

        return Response({
            "detail": "Mot de passe changé avec succès"
        })
