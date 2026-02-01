export interface Issue {
  ruleId: string;
  severity: 'critical' | 'error' | 'warning';
  file: string;
  line: number;
  column: number;
  message: string;
  suggestion?: string;
  autoFixable: boolean;
  code?: string;
}

export interface ScanResult {
  issues: Issue[];
  summary: {
    filesScanned: number;
    total: number;
    critical: number;
    errors: number;
    warnings: number;
    autoFixable: number;
  };
}

export interface DetectorContext {
  filePath: string;
  code: string;
}

export interface Detector {
  name: string;
  detect(context: DetectorContext): Issue[];
}
