import { parse } from '@babel/parser';
import traverse from '@babel/traverse';
import * as t from '@babel/types';
import { Detector, DetectorContext, Issue } from '../types';

export class FetchDetector implements Detector {
  name = 'fetch-detector';

  detect(context: DetectorContext): Issue[] {
    const issues: Issue[] = [];

    try {
      const ast = parse(context.code, {
        sourceType: 'module',
        plugins: ['typescript', 'jsx'],
      });

      traverse(ast, {
        CallExpression: (path) => {
          // Check if this is a fetch() call
          const callee = path.node.callee;
          if (t.isIdentifier(callee) && callee.name === 'fetch') {
            const firstArg = path.node.arguments[0];

            // Check for string literal starting with /
            if (t.isStringLiteral(firstArg) && firstArg.value.startsWith('/')) {
              issues.push({
                ruleId: 'absolute-fetch-url',
                severity: 'error',
                file: context.filePath,
                line: firstArg.loc?.start.line || 0,
                column: firstArg.loc?.start.column || 0,
                message: `fetch() uses absolute path '${firstArg.value}'`,
                suggestion: `Wrap with base URL helper: fetch(apiUrl('${firstArg.value}'))`,
                autoFixable: true,
                code: context.code.split('\n')[firstArg.loc?.start.line ? firstArg.loc.start.line - 1 : 0]?.trim(),
              });
            }

            // Check for template literal starting with /
            if (t.isTemplateLiteral(firstArg)) {
              const firstQuasi = firstArg.quasis[0];
              if (firstQuasi && firstQuasi.value.raw.startsWith('/')) {
                issues.push({
                  ruleId: 'absolute-fetch-url',
                  severity: 'error',
                  file: context.filePath,
                  line: firstArg.loc?.start.line || 0,
                  column: firstArg.loc?.start.column || 0,
                  message: `fetch() uses absolute path template literal starting with '${firstQuasi.value.raw}'`,
                  suggestion: 'Wrap with base URL helper: fetch(apiUrl(`/your/path`))',
                  autoFixable: true,
                  code: context.code.split('\n')[firstArg.loc?.start.line ? firstArg.loc.start.line - 1 : 0]?.trim(),
                });
              }
            }
          }
        },
      });
    } catch (error) {
      // Skip files that can't be parsed
      console.error(`Error parsing ${context.filePath}:`, error instanceof Error ? error.message : String(error));
    }

    return issues;
  }
}
