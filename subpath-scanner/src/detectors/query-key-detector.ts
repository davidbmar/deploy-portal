import { parse } from '@babel/parser';
import traverse from '@babel/traverse';
import * as t from '@babel/types';
import { Detector, DetectorContext, Issue } from '../types';

export class QueryKeyDetector implements Detector {
  name = 'query-key-detector';

  detect(context: DetectorContext): Issue[] {
    const issues: Issue[] = [];

    try {
      const ast = parse(context.code, {
        sourceType: 'module',
        plugins: ['typescript', 'jsx'],
      });

      traverse(ast, {
        // Detect queryKey: ['/api/...']
        ObjectProperty: (path) => {
          const key = path.node.key;
          if (t.isIdentifier(key) && key.name === 'queryKey') {
            const value = path.node.value;

            // Check if value is an array
            if (t.isArrayExpression(value)) {
              value.elements.forEach((element) => {
                if (t.isStringLiteral(element) && element.value.startsWith('/')) {
                  issues.push({
                    ruleId: 'query-key-absolute-path',
                    severity: 'error',
                    file: context.filePath,
                    line: element.loc?.start.line || 0,
                    column: element.loc?.start.column || 0,
                    message: `queryKey contains absolute path '${element.value}'`,
                    suggestion: 'Remove leading slash or use relative path',
                    autoFixable: true,
                    code: context.code.split('\n')[element.loc?.start.line ? element.loc.start.line - 1 : 0]?.trim(),
                  });
                }
              });
            }
          }
        },

        // Detect queryKey.join('/') - Critical architectural issue
        CallExpression: (path) => {
          const callee = path.node.callee;

          // Check if this is a .join() call
          if (
            t.isMemberExpression(callee) &&
            t.isIdentifier(callee.property) &&
            callee.property.name === 'join'
          ) {
            // Check if the object is 'queryKey' or contains 'queryKey'
            const objectName = this.getObjectName(callee.object);
            if (objectName && objectName.includes('queryKey')) {
              // Check if join argument is '/'
              const joinArg = path.node.arguments[0];
              if (t.isStringLiteral(joinArg) && joinArg.value === '/') {
                issues.push({
                  ruleId: 'query-fn-url-join',
                  severity: 'critical',
                  file: context.filePath,
                  line: path.node.loc?.start.line || 0,
                  column: path.node.loc?.start.column || 0,
                  message: 'queryKey.join(\'/\') used to construct URL - ARCHITECTURAL ISSUE',
                  suggestion: 'Refactor to separate query keys from URL construction. Use a base URL helper instead.',
                  autoFixable: false,
                  code: context.code.split('\n')[path.node.loc?.start.line ? path.node.loc.start.line - 1 : 0]?.trim(),
                });
              }
            }
          }
        },
      });
    } catch (error) {
      console.error(`Error parsing ${context.filePath}:`, error instanceof Error ? error.message : String(error));
    }

    return issues;
  }

  private getObjectName(node: t.Node): string | null {
    if (t.isIdentifier(node)) {
      return node.name;
    }
    if (t.isMemberExpression(node)) {
      const objectName = this.getObjectName(node.object);
      const propertyName = t.isIdentifier(node.property) ? node.property.name : null;
      return objectName && propertyName ? `${objectName}.${propertyName}` : objectName;
    }
    return null;
  }
}
