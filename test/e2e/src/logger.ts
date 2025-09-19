/**
 * Centralized logging system for E2E tests
 * Provides consistent logging with levels and formatting
 */

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

export interface LoggerConfig {
  level: LogLevel;
  enableColors: boolean;
  enableTimestamps: boolean;
}

class Logger {
  private config: LoggerConfig;

  constructor(config: LoggerConfig = {
    level: LogLevel.INFO,
    enableColors: true,
    enableTimestamps: false,
  }) {
    this.config = config;
  }

  private shouldLog(level: LogLevel): boolean {
    return level >= this.config.level;
  }

  private formatMessage(level: LogLevel, prefix: string, message: string, ...args: unknown[]): string {
    const timestamp = this.config.enableTimestamps ? `[${new Date().toISOString()}] ` : '';
    const levelStr = LogLevel[level];
    const formattedArgs = args.length > 0 ? ' ' + args.map(arg => 
      typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)
    ).join(' ') : '';
    
    return `${timestamp}${prefix} ${message}${formattedArgs}`;
  }

  debug(prefix: string, message: string, ...args: unknown[]): void {
    if (this.shouldLog(LogLevel.DEBUG)) {
      console.log(this.formatMessage(LogLevel.DEBUG, prefix, message, ...args));
    }
  }

  info(prefix: string, message: string, ...args: unknown[]): void {
    if (this.shouldLog(LogLevel.INFO)) {
      console.log(this.formatMessage(LogLevel.INFO, prefix, message, ...args));
    }
  }

  warn(prefix: string, message: string, ...args: unknown[]): void {
    if (this.shouldLog(LogLevel.WARN)) {
      console.warn(this.formatMessage(LogLevel.WARN, prefix, message, ...args));
    }
  }

  error(prefix: string, message: string, ...args: unknown[]): void {
    if (this.shouldLog(LogLevel.ERROR)) {
      console.error(this.formatMessage(LogLevel.ERROR, prefix, message, ...args));
    }
  }

  setLevel(level: LogLevel): void {
    this.config.level = level;
  }

  setConfig(config: Partial<LoggerConfig>): void {
    this.config = { ...this.config, ...config };
  }
}

// Export a default logger instance
export const logger = new Logger();

// Export the Logger class for custom instances
export { Logger };
