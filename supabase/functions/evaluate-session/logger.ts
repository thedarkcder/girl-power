interface LogMeta {
  [key: string]: unknown;
}

export type Logger = {
  info: (message: string, meta?: LogMeta) => void;
  warn: (message: string, meta?: LogMeta) => void;
  error: (message: string, meta?: LogMeta) => void;
};

export function createLogger(component: string): Logger {
  const log = (level: 'info' | 'warn' | 'error', message: string, meta: LogMeta = {}) => {
    const payload = {
      level,
      component,
      message,
      timestamp: new Date().toISOString(),
      ...meta,
    };
    console[level === 'info' ? 'log' : level](JSON.stringify(payload));
  };

  return {
    info: (message, meta) => log('info', message, meta),
    warn: (message, meta) => log('warn', message, meta),
    error: (message, meta) => log('error', message, meta),
  };
}
