/**
 * API Client for CityScape Creator Interface
 * Communicates with Django REST API
 */

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'https://api.cityscape.ovh';

class ApiClient {
  constructor() {
    this.token = localStorage.getItem('auth_token');
  }

  setToken(token) {
    this.token = token;
    if (token) {
      localStorage.setItem('auth_token', token);
    } else {
      localStorage.removeItem('auth_token');
    }
  }

  getHeaders() {
    const headers = {
      'Content-Type': 'application/json',
    };

    if (this.token) {
      headers['Authorization'] = `Token ${this.token}`;
    }

    return headers;
  }

  async request(endpoint, options = {}) {
    const url = `${API_BASE_URL}${endpoint}`;
    const config = {
      ...options,
      headers: {
        ...this.getHeaders(),
        ...options.headers,
      },
    };

    try {
      const response = await fetch(url, config);

      if (!response.ok) {
        const error = await response.json().catch(() => ({ detail: response.statusText }));
        throw new Error(error.detail || `HTTP ${response.status}`);
      }

      // Handle 204 No Content
      if (response.status === 204) {
        return null;
      }

      return await response.json();
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  }

  // Auth endpoints
  async login(username, password) {
    const response = await this.request('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    });
    this.setToken(response.token);
    return response;
  }

  async register(username, email, password) {
    const response = await this.request('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify({ username, email, password }),
    });
    return response;
  }

  async logout() {
    this.setToken(null);
  }

  // User profile endpoints
  async getUserProfile() {
    return await this.request('/api/auth/profile');
  }

  async updateUserProfile(data) {
    return await this.request('/api/auth/profile', {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async changePassword(oldPassword, newPassword) {
    return await this.request('/api/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({
        old_password: oldPassword,
        new_password: newPassword,
      }),
    });
  }

  // Escape endpoints
  async getMyEscapes() {
    return await this.request('/api/creator/escapes');
  }

  async getEscape(id) {
    return await this.request(`/api/creator/escapes/${id}`);
  }

  async createEscape(data) {
    return await this.request('/api/creator/escapes', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async updateEscape(id, data) {
    return await this.request(`/api/creator/escapes/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async deleteEscape(id) {
    return await this.request(`/api/creator/escapes/${id}`, {
      method: 'DELETE',
    });
  }

  async submitEscape(id) {
    return await this.request(`/api/creator/escapes/${id}/submit`, {
      method: 'POST',
    });
  }

  // Step endpoints
  async getSteps(escapeId) {
    return await this.request(`/api/creator/escapes/${escapeId}/steps`);
  }

  async createStep(escapeId, data) {
    return await this.request(`/api/creator/escapes/${escapeId}/steps`, {
      method: 'POST',
      body: JSON.stringify(data),
    });
  }

  async updateStep(escapeId, stepId, data) {
    return await this.request(`/api/creator/escapes/${escapeId}/steps/${stepId}`, {
      method: 'PATCH',
      body: JSON.stringify(data),
    });
  }

  async deleteStep(escapeId, stepId) {
    return await this.request(`/api/creator/escapes/${escapeId}/steps/${stepId}`, {
      method: 'DELETE',
    });
  }

  // Image upload
  async uploadImage(file) {
    const formData = new FormData();
    formData.append('image', file);

    const url = `${API_BASE_URL}/api/creator/upload_image`;
    const headers = {};

    if (this.token) {
      headers['Authorization'] = `Token ${this.token}`;
    }

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: formData,
    });

    if (!response.ok) {
      throw new Error('Image upload failed');
    }

    return await response.json();
  }
}

export default new ApiClient();
