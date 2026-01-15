import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import EscapeEditor from './pages/EscapeEditor';
import Profile from './pages/Profile';
import './styles/globals.css';

function App() {
  return (
    <BrowserRouter basename="/creator">
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/escape/:id" element={<EscapeEditor />} />
        <Route path="/profile" element={<Profile />} />
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
