import request from './request'

export function fetchUserInfo() {
  return request.get('/api/userInfo')
}

export function logout() {
  return request.post('/perform_logout')
}
