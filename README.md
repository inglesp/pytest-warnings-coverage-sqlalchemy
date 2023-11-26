# pytest-warnings-coverage-sqlalchemy

This repo demonstrates a nasty interaction between the following:

 * the way pytest handles warnings,
 * the way Coverage.py handles editable installs, and
 * some import-time caching in SQLAlchemy.

Specifically, the following command
runs fine when run in an virtual environment where this package has not been installed in editable mode,
but hits a SQLAlchemy exception when it has been.

```
pytest -Wignore:XXX:sqlalchemy.exc.SADeprecationWarning --cov=package.module test.py
```

See also opensafely-core/ehrql#1537.

To reproduce, first run `./setup.sh`, which creates two virtual environments:

 * .venv-1 does not contain this package in editable mode;
 * .venv-2 does.

Then run `./run.sh 1` to run the command in .venv-1.
You'll see that a single test runs and passes, and you'll see some expected coverage warnings.

And run `./run.sh 2` to run the same command in .venv-2.
This time, you'll see a collection error from pytest, caused by an assertion from sqlalchemy/inspection.py.

## What's going on?

First, [pytest imports](https://github.com/pytest-dev/pytest/blob/85e0f676c5a545f71cfedb143a75268cda0aadaa/src/_pytest/config/__init__.py#L1878-L1897) `sqlalchemy.exc`
in order to validate the warnings filter.
This partially populates the [`sqlalchemy.inspection._registrars`](https://github.com/sqlalchemy/sqlalchemy/blob/66be1482db06adb908432b2e3b41d9393d1319f7/lib/sqlalchemy/inspection.py#L53) cache
via [this decorator](https://github.com/sqlalchemy/sqlalchemy/blob/66be1482db06adb908432b2e3b41d9393d1319f7/lib/sqlalchemy/inspection.py#L159-L171).

Next, [Coverage.py tries to import](https://github.com/nedbat/coveragepy/blob/32681c81ef8c8933aa404edad4513dbe21306119/coverage/inorout.py#L124-L142) `package.module`
(which doesn't exist, but that's not important here).
Before it does so, it [records the contents of `sys.modules`, and restores it afterwards](https://github.com/nedbat/coveragepy/blob/32681c81ef8c8933aa404edad4513dbe21306119/coverage/inorout.py#L266).

`package` can only be imported when it has been installed in editable mode,
because the current directory is not on `sys.path`.

Since `package.__init__` imports `sqlalchemy.orm`,
several modules from the `sqlalchemy` package are imported,
which further populates the `sqlalchemy.inspection._registrars` cache.

**But the `sqlalchemy` modules are temporarily imported, while the the cache is permanently updated.**

So when `sqlalchemy.orm` is imported in `test.py`, the `sqlalchemy` modules are loaded again from scratch
(instead of being retrieved from `sys.modules`)
and so various objects are added to the cache again...
except that [keys can only be added to the cache once](https://github.com/sqlalchemy/sqlalchemy/blob/66be1482db06adb908432b2e3b41d9393d1319f7/lib/sqlalchemy/inspection.py#L164-L167),
which causes the exception.

You can see this play out here:

```
>>> import sys
>>> import sqlalchemy.exc
>>> old_modules = set(sys.modules)
>>> import sqlalchemy.orm
>>> new_modules = set(sys.modules) - old_modules
>>> for m in new_modules: del sys.modules[m]
... 
>>> import sqlalchemy.orm
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/inglesp/tmp/pytest-warnings-coverage-sqlalchemy/.venv-2/lib/python3.11/site-packages/sqlalchemy/orm/__init__.py", line 21, in <module>
    from . import mapper as mapperlib
  File "/home/inglesp/tmp/pytest-warnings-coverage-sqlalchemy/.venv-2/lib/python3.11/site-packages/sqlalchemy/orm/mapper.py", line 47, in <module>
    from . import attributes
  File "/home/inglesp/tmp/pytest-warnings-coverage-sqlalchemy/.venv-2/lib/python3.11/site-packages/sqlalchemy/orm/attributes.py", line 39, in <module>
    from . import collections
  File "/home/inglesp/tmp/pytest-warnings-coverage-sqlalchemy/.venv-2/lib/python3.11/site-packages/sqlalchemy/orm/collections.py", line 128, in <module>
    from .base import NO_KEY
  File "/home/inglesp/tmp/pytest-warnings-coverage-sqlalchemy/.venv-2/lib/python3.11/site-packages/sqlalchemy/orm/base.py", line 432, in <module>
    @inspection._inspects(object)
     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/inglesp/tmp/pytest-warnings-coverage-sqlalchemy/.venv-2/lib/python3.11/site-packages/sqlalchemy/inspection.py", line 165, in decorate
    raise AssertionError(
AssertionError: Type <class 'object'> is already registered
```
