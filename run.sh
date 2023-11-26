. .venv-$1/bin/activate
pytest -Wignore:XXX:sqlalchemy.exc.SADeprecationWarning --cov=package.module test.py
. deactivate
