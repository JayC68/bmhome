import * as Joi from 'joi';

export interface BMHomeConfig {
  platform?: string;
  name: string;
  clientId: string;
  vin?: string;
  enableStreaming: boolean;
  pollingInterval: number;
}

const configSchema = Joi.object({
  platform: Joi.string().optional(),
  name: Joi.string().default('BM Home'),
  clientId: Joi.string().required().min(10).description('BMW CarData Client ID'),
  vin: Joi.string().length(17).allow('').optional(),
  enableStreaming: Joi.boolean().default(true),
  pollingInterval: Joi.number().min(60).default(180),
}).unknown(true);

export function validateConfig(config: unknown): BMHomeConfig {
  const { error, value } = configSchema.validate(config, {
    abortEarly: false,
    stripUnknown: false,
  });

  if (error) {
    throw new Error(`Invalid BMHome config: ${error.message}`);
  }

  return value as BMHomeConfig;
}
