import chalk from 'chalk';
import { ScanResult, Issue } from '../types';

export class ConsoleReporter {
  report(result: ScanResult): void {
    console.log();
    console.log(chalk.cyan('═'.repeat(70)));
    console.log(chalk.cyan.bold('  Subpath Deployment Scanner v0.1.0'));
    console.log(chalk.cyan('═'.repeat(70)));
    console.log();

    const { critical, errors, warnings } = this.groupBySeverity(result.issues);

    if (critical.length > 0) {
      console.log(chalk.red.bold(`CRITICAL ISSUES (${critical.length})`));
      console.log();
      critical.forEach((issue) => this.printIssue(issue));
      console.log();
    }

    if (errors.length > 0) {
      console.log(chalk.yellow.bold(`ERRORS (${errors.length})`));
      console.log();
      errors.forEach((issue) => this.printIssue(issue));
      console.log();
    }

    if (warnings.length > 0) {
      console.log(chalk.blue.bold(`WARNINGS (${warnings.length})`));
      console.log();
      warnings.forEach((issue) => this.printIssue(issue));
      console.log();
    }

    if (result.issues.length === 0) {
      console.log(chalk.green.bold('✓ No issues found!'));
      console.log();
    }

    this.printSummary(result);
  }

  private groupBySeverity(issues: Issue[]): {
    critical: Issue[];
    errors: Issue[];
    warnings: Issue[];
  } {
    return {
      critical: issues.filter((i) => i.severity === 'critical'),
      errors: issues.filter((i) => i.severity === 'error'),
      warnings: issues.filter((i) => i.severity === 'warning'),
    };
  }

  private printIssue(issue: Issue): void {
    const icon = issue.severity === 'critical' ? '✖✖' : '✖';
    const color = issue.severity === 'critical' ? chalk.red : chalk.yellow;

    console.log(color(`  ${icon} ${issue.ruleId}`));
    console.log(chalk.gray(`    File: ${issue.file}:${issue.line}:${issue.column}`));
    console.log();
    console.log(`    ${issue.message}`);

    if (issue.code) {
      console.log();
      console.log(chalk.gray(`    ${issue.code}`));
    }

    if (issue.suggestion) {
      console.log();
      console.log(chalk.cyan(`    Fix: ${issue.suggestion}`));
    }

    console.log(chalk.gray(`    Auto-fixable: ${issue.autoFixable ? 'Yes (Phase 2)' : 'No'}`));
    console.log();
  }

  private printSummary(result: ScanResult): void {
    console.log(chalk.cyan.bold('SUMMARY'));
    console.log(`  Files scanned: ${result.summary.filesScanned}`);
    console.log(
      `  Issues found: ${result.summary.total} ` +
        `(Critical: ${result.summary.critical}, ` +
        `Errors: ${result.summary.errors}, ` +
        `Warnings: ${result.summary.warnings})`
    );
    console.log(`  Auto-fixable: ${result.summary.autoFixable} (Phase 2 feature)`);
    console.log();

    if (result.summary.total > 0) {
      console.log(chalk.yellow.bold('NEXT STEPS'));
      console.log('  1. Review issues above');
      console.log('  2. Fix absolute paths to use base URL helper');
      console.log('  3. Re-scan: npx subpath-scanner scan');
      console.log();
    }
  }
}
