import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import apiClient from '../api/client';
import '../styles/globals.css';

// Même client ID que l'app mobile (serverClientId). Le backend valide déjà
// les tokens contre cet identifiant : rien à changer côté serveur.
const GOOGLE_CLIENT_ID =
  import.meta.env.VITE_GOOGLE_CLIENT_ID ||
  '622564437605-fludcb1jo2157oi7ejbg25jju9d6qeht.apps.googleusercontent.com';

function Login() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const googleBtnRef = useRef(null);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      await apiClient.login(username, password);
      navigate('/dashboard');
    } catch (err) {
      setError(err.message || 'Erreur de connexion. Vérifiez vos identifiants.');
    } finally {
      setLoading(false);
    }
  };

  // Connexion Google (Google Identity Services). Le bouton officiel Google est
  // rendu dans googleBtnRef ; à la réception du credential (ID token), on
  // l'envoie au même endpoint que le mobile (/api/auth/google).
  useEffect(() => {
    const handleCredential = async (response) => {
      setError('');
      setLoading(true);
      try {
        await apiClient.googleLogin(response.credential);
        navigate('/dashboard');
      } catch (err) {
        setError(err.message || 'Connexion Google échouée.');
      } finally {
        setLoading(false);
      }
    };

    const initGoogle = () => {
      if (!window.google || !googleBtnRef.current) return;
      window.google.accounts.id.initialize({
        client_id: GOOGLE_CLIENT_ID,
        callback: handleCredential,
      });
      window.google.accounts.id.renderButton(googleBtnRef.current, {
        theme: 'outline',
        size: 'large',
        width: 360,
        text: 'signin_with',
        locale: 'fr',
      });
    };

    if (window.google?.accounts?.id) {
      initGoogle();
      return;
    }

    const existing = document.getElementById('google-gsi');
    if (existing) {
      existing.addEventListener('load', initGoogle);
      return () => existing.removeEventListener('load', initGoogle);
    }

    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.id = 'google-gsi';
    script.async = true;
    script.defer = true;
    script.onload = initGoogle;
    document.body.appendChild(script);
  }, [navigate]);

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px' }}>
      <div className="card" style={{ maxWidth: '400px', width: '100%' }}>
        <div style={{ textAlign: 'center', marginBottom: '30px' }}>
          <div style={{ fontSize: '48px', marginBottom: '10px' }}>🏙️</div>
          <h1>CityScape Creator</h1>
          <p>Connectez-vous pour créer vos escapes</p>
        </div>

        {error && (
          <div className="alert alert-error">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label" htmlFor="username">
              Nom d'utilisateur
            </label>
            <input
              id="username"
              type="text"
              className="form-input"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
              autoComplete="username"
              disabled={loading}
            />
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="password">
              Mot de passe
            </label>
            <input
              id="password"
              type="password"
              className="form-input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              disabled={loading}
            />
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%' }}
            disabled={loading}
          >
            {loading ? 'Connexion...' : 'Se connecter'}
          </button>
        </form>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', margin: '20px 0', color: 'var(--text-muted)', fontSize: '13px' }}>
          <span style={{ flex: 1, height: '1px', background: 'var(--border, #ddd)' }} />
          ou
          <span style={{ flex: 1, height: '1px', background: 'var(--border, #ddd)' }} />
        </div>

        <div style={{ display: 'flex', justifyContent: 'center' }}>
          <div ref={googleBtnRef} />
        </div>

        <div style={{ marginTop: '20px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '14px' }}>
          <p>Pas encore de compte ? Contactez-nous pour devenir créateur.</p>
        </div>
      </div>
    </div>
  );
}

export default Login;
