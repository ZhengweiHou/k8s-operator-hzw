import os, sys, yaml

class Config:
    def __init__(self):
        self.config = None

    def load_config(self):
        with open(os.path.join(sys.path[0], "db2.yml"), "r") as c:
            self.config = yaml.load(c)

    def is_prod(self):
        return self.config["env"] == "prod"

    def is_stage(self):
        return self.config["env"] == "stage"

    def __getitem__(self, key):
        return self.config[key]

config = Config()
