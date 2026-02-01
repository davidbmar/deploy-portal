#!/usr/bin/env node

import { Command } from 'commander';
import * as path from 'path';
import { Scanner } from './scanner';
import { ConsoleReporter } from './reporters/console-reporter';

const program = new Command();

program
  .name('subpath-scanner')
  .description('AST-based scanner for detecting absolute path issues in SPAs deployed to subpaths')
  .version('0.1.0');

program
  .command('scan')
  .description('Scan a directory for subpath deployment issues')
  .option('-d, --dir <directory>', 'Directory to scan', process.cwd())
  .option('-f, --format <format>', 'Output format (console|json)', 'console')
  .action(async (options) => {
    const directory = path.resolve(options.dir);
    console.log(`Starting scan of: ${directory}`);
    console.log();

    const scanner = new Scanner();
    const result = await scanner.scan(directory);

    if (options.format === 'json') {
      console.log(JSON.stringify(result, null, 2));
    } else {
      const reporter = new ConsoleReporter();
      reporter.report(result);
    }

    // Exit with error code if issues found
    process.exit(result.summary.total > 0 ? 1 : 0);
  });

program.parse();
