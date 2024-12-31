# Sample app for SQL Injection

## Databases

You can find examples of how to start and configure the different databases 
in the Github workflows directory.

**Sqlite3**
Set the following environment variable :
```env
DATABASE_URL=sqlite3:storage/test.salite3
```

**Trilogy**
Set the following environment variable :
```env
DATABASE_URL=trilogy://root:@127.0.0.1:3306/cats_test
```

**PostgreSQL**
Set the following environment variable :
```env
DATABASE_URL=postgresql://postgres:password@127.0.0.1:5432/cats_test
```

**MySQL**
Set the following environment variable :
```env
DATABASE_URL=mysql2://root:@127.0.0.1:3306/cats_test
```
