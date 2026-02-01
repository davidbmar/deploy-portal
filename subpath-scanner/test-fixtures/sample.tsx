// Test file with absolute path issues

export function fetchData() {
  // Should be detected: absolute fetch URL
  return fetch('/api/sessions');
}

export function fetchWithTemplate(id: string) {
  // Should be detected: template literal with absolute path
  return fetch(`/api/sessions/${id}/transcripts`);
}

export const useStats = () => {
  return useQuery({
    // Should be detected: queryKey with absolute path
    queryKey: ['/api/stats'],
    queryFn: () => fetch('/api/stats'),
  });
};

// Critical issue: queryKey.join('/')
export const useQueryJoin = () => {
  return useQuery({
    queryKey: ['api', 'sessions'],
    queryFn: ({ queryKey }) => fetch(queryKey.join('/')),  // CRITICAL
  });
};
