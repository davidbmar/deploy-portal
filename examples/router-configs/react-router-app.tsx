/**
 * CORRECT React Router Configuration for Subpath Deployments
 *
 * Use this as a template when deploying apps to subpaths like /app-name/
 *
 * Key changes:
 * 1. Add basename prop to BrowserRouter
 */

import { BrowserRouter, Routes, Route } from "react-router-dom";
import Dashboard from "./pages/dashboard";
import StatsPage from "./pages/stats";
import NotFound from "./pages/not-found";

function App() {
  return (
    <BrowserRouter basename="/app-name">  {/* ✅ CRITICAL: Add basename */}
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/stats" element={<StatsPage />} />
        <Route path="*" element={<NotFound />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;

/**
 * COMMON MISTAKES:
 *
 * ❌ WRONG - Missing basename:
 *    <BrowserRouter>
 *      <Routes>...</Routes>
 *    </BrowserRouter>
 *
 * ✅ CORRECT - With basename:
 *    <BrowserRouter basename="/app-name">
 *      <Routes>...</Routes>
 *    </BrowserRouter>
 *
 * Documentation: https://reactrouter.com/en/main/router-components/browser-router#basename
 */
