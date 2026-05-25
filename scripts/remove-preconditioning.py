from pathlib import Path
import re

p = Path("src/vehicleAccessory.ts")
s = p.read_text()

s = s.replace("  private heaterService!: Service;\n", "")

s = re.sub(
    r"\n    this\.heaterService =\n      accessory\.getService\(api\.hap\.Service\.HeaterCooler\) \?\?\n      accessory\.addService\(api\.hap\.Service\.HeaterCooler, 'BMW Preconditioning', 'heat'\);\n",
    "\n",
    s,
)

s = s.replace("    this.setServiceName(this.heaterService, 'BMW Preconditioning');\n", "")

s = re.sub(
    r"\n    this\.heaterService\n      \.getCharacteristic\(Characteristic\.Active\)\n      \.onSet\(async \(value\) => \{\n        const result = await this\.client\.precondition\(\n          this\.vin,\n          value === Characteristic\.Active\.ACTIVE,\n        \);\n\n        this\.log\.warn\(result\.message\);\n      \}\);\n",
    "\n",
    s,
)

s = re.sub(
    r"\n    if \(data\.preconditionActive !== undefined\) \{\n      this\.heaterService\.updateCharacteristic\(\n        Characteristic\.Active,\n        data\.preconditionActive \? Characteristic\.Active\.ACTIVE : Characteristic\.Active\.INACTIVE,\n      \);\n    \}\n",
    "\n",
    s,
)

p.write_text(s)
print("Removed legacy Preconditioning/HeaterCooler service from src/vehicleAccessory.ts")
