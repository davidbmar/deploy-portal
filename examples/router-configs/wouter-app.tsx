/**
 * CORRECT Wouter Router Configuration for Subpath Deployments
 *
 * Use this as a template when deploying apps to subpaths like /app-name/
 *
 * Key changes:
 * 1. Import Router from "wouter"
 * 2. Wrap Switch in <Router base="/app-name">
 * 3. Keep route paths as-is (no changes needed)
 */

import { Router, Switch, Route } from "wouter";  // ✅ Import Router
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "./lib/queryClient";

// Example pages
import Dashboard from "./pages/dashboard";
import StatsPage from "./pages/stats";
import SessionsPage from "./pages/sessions";
import NotFound from "./pages/not-found";

function AppRouter() {
  return (
    <Router base="/app-name">  {/* ✅ CRITICAL: Add Router with base path */}
      <Switch>
        <Route path="/" component={Dashboard} />
        <Route path="/stats" component={StatsPage} />
        <Route path="/sessions" component={SessionsPage} />
        <Route component={NotFound} />
      </Switch>
    </Router>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AppRouter />
    </QueryClientProvider>
  );
}

export default App;

/**
 * COMMON MISTAKES:
 *
 * ❌ WRONG - Missing Router wrapper:
 *    <Switch>
 *      <Route path="/" component={Dashboard} />
 *    </Switch>
 *
 * ❌ WRONG - No base prop:
 *    <Router>
 *      <Switch>...</Switch>
 *    </Router>
 *
 * ✅ CORRECT - Router with base:
 *    <Router base="/app-name">
 *      <Switch>...</Switch>
 *    </Router>
 */
