@echo off
echo ==================================================
echo Empreintes SHA du keystore de PRODUCTION
echo ==================================================
echo.
echo Entrez le mot de passe du keystore quand demande:
echo.
keytool -list -v -keystore C:\Users\lougi\keystores\cityscape.jks
echo.
echo ==================================================
echo Copiez les lignes SHA 1 et SHA 256 ci-dessus
echo ==================================================
pause
