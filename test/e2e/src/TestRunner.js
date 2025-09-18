const fs = require('fs');
const path = require('path');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');

class TestRunner {
  constructor() {
    this.ajv = new Ajv({ 
      allErrors: true,
      strict: false  // Allow draft-2020-12 schemas
    });
    addFormats(this.ajv);
    this.loadSchemas();
  }

  loadSchemas() {
    const schemaDir = path.join(__dirname, '../schemas');
    this.schemas = {};
    
    const schemaFiles = fs.readdirSync(schemaDir);
    schemaFiles.forEach(file => {
      if (file.endsWith('.json')) {
        const schemaName = file.replace('.json', '');
        const schemaPath = path.join(schemaDir, file);
        this.schemas[schemaName] = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
      }
    });
  }

  validateSetup(setupData) {
    const validate = this.ajv.compile(this.schemas.testSetupSchema);
    const valid = validate(setupData);
    if (!valid) {
      throw new Error(`Setup validation failed: ${JSON.stringify(validate.errors, null, 2)}`);
    }
    return true;
  }

  validateInteraction(interactionData) {
    const validate = this.ajv.compile(this.schemas.tokenInteractionSchema);
    const valid = validate(interactionData);
    if (!valid) {
      throw new Error(`Interaction validation failed: ${JSON.stringify(validate.errors, null, 2)}`);
    }
    return true;
  }

  loadTestInstance(type, filename) {
    const filePath = path.join(__dirname, `../instances/${type}/${filename}`);
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  }

  getAllTestInstances(type) {
    const instancesDir = path.join(__dirname, `../instances/${type}`);
    if (!fs.existsSync(instancesDir)) return [];
    
    return fs.readdirSync(instancesDir)
      .filter(file => file.endsWith('.json'))
      .map(file => ({
        filename: file,
        data: this.loadTestInstance(type, file)
      }));
  }
}

module.exports = TestRunner;
