import * as Joi from 'joi';
import { BMHomePlatformConfig } from './types';

const configSchema = Joi.object<BMHomePlatformConfig>({
  name: Joi.string().default('BMW Home'),
  clientId: Joi.string().required().min(10).description('BMW CarData Client ID'),
  vin: Joi.string().length(17).allow('').optional(),
  enableStreaming: Joi.boolean().default(true),
  pollingInterval: Joi.number().min(60).default(180),
});

export function validateConfig(config: any): BMHomePlatformConfig {
  const { error, value } = configSchema.validate(config, { abortEarly: false });

  if (error) {
    throw new Error(`Invalid BMHome config: ${error.message}`);
  }

  return value;
}
