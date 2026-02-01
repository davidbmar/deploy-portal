import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import { FetchDetector, QueryKeyDetector } from './detectors';
import { ScanResult, Issue, Detector } from './types';

export class Scanner {
  private detectors: Detector[];

  constructor() {
    this.detectors = [
      new FetchDetector(),
      new QueryKeyDetector(),
    ];
  }

  async scan(directory: string): Promise<ScanResult> {
    const issues: Issue[] = [];

    // Find all TypeScript and JavaScript files, excluding node_modules
    const files = await glob('**/*.{ts,tsx,js,jsx}', {
      cwd: directory,
      ignore: ['**/node_modules/**', '**/dist/**', '**/build/**', '**/.next/**'],
      absolute: true,
    });

    console.log(`Scanning ${files.length} files in ${directory}...`);
    console.log();

    for (const file of files) {
      try {
        const code = fs.readFileSync(file, 'utf-8');
        const relativePath = path.relative(directory, file);

        for (const detector of this.detectors) {
          const detectorIssues = detector.detect({
            filePath: relativePath,
            code,
          });
          issues.push(...detectorIssues);
        }
      } catch (error) {
        // Skip files that can't be read
        console.error(`Error reading ${file}:`, error instanceof Error ? error.message : String(error));
      }
    }

    // Calculate summary
    const summary = {
      filesScanned: files.length,
      total: issues.length,
      critical: issues.filter((i) => i.severity === 'critical').length,
      errors: issues.filter((i) => i.severity === 'error').length,
      warnings: issues.filter((i) => i.severity === 'warning').length,
      autoFixable: issues.filter((i) => i.autoFixable).length,
    };

    return {
      issues,
      summary,
    };
  }
}
