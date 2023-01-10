Deployment on Azure
====================

.. index:: Azure

Architecture
------

This app can be configured for deployment to Microsoft Azure, using Azure resources
for the various app components whenever possible. This diagram shows the resources used:

![Diagram of Azure architecture](https://i.imgur.com/VyFtlVT.png)

The app is hosted on `Azure App Service`_, and the database is an `Azure PostgreSQL Flexible Server`_,
protected inside an `Azure Virtual Network`_ and `Private DNS Zone`_ to prevent external access.
The app caching uses `Azure Cache for Redis`_. The celery queue also uses that Redis cache,
and the celery beat scheduler uses the app's PostgreSQL database.
The media storage uses `Azure Blob Storage`_, configured for public read-only access.

.. _Azure App Service: https://devcenter.heroku.com/articles/build-docker-images-heroku-yml

The resources are declared programmatically using the `Bicep_` language (similar to Terraform),
so any customizations of the architecture should be made to the `bicep` files inside the `infra` folder.

Cookie-cutter configuration
------

* When prompted for `use_docker`, enter "n"
   * Azure does have support for Docker, in various services (App Service, Container Apps, Kubernetes Service).
However, for simplicity's sake, this integration does not use the Docker option.
* When prompted for `cloud_storage`, select "Azure"
* When prompted for `use_azure`, enter "y"
* When prompted for `use_whitenoise`, enter "y"
* When prompted for `mail_service`, select whichever mail provider you are most comfortable with. At this time, no Azure email service is supported by the `django-anymail` service.

The other generation options are up to you; they should all be compatible with Azure.

Deployment
------

Once the project is generated, follow these steps to deploy the app:

1. Sign up for an [Azure account](https://azure.microsoft.com/free)
2. Install the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
3. Provision and deploy all the resources:

```
azd up
```

4. If all goes well, you'll see the app URL displayed. Navigate to that URL in your browser to load the app. 

Post-Deployment
-----

Django admin
+++++++++++++

You'll need to create a superuser to be able to login to Django admin.

First navigate to the Azure Portal for the App Service (using either the link displayed after the deployment step
or by going to portal.azure.com).

Select **SSH** to start a SSH session on the App Service container. Inside that session, run::

```
python manage.py createsuperuser
```

Store your credentials in a secure place, like a password manager.

For security reasons, on production, Django admin is made accessible on a URL that isn't simply "/admin".
To discover the admin URL for your app, navigate to the Azure Portal for the App Service,
open the **Configuration settings** and inspect `DJANGO_ADMIN_URL` setting.

Now you can navigate to <your app url>/<your admin url>, enter the superuser credentials,
and use Django admin.

Email Service
+++++++++++++

The `django-anymail` package doesn't support any Azure offerings for e-mail services,
so you'll need to use one of the options in the cookie-cutter configuration.

Each of the e-mail services has a corresponding API key which is set as an environment variable.

After your first deploy, you'll need to add that API key as a secret to the resource group's Key Vault.
Key Vault secrets can't contain underscores, so the secret name must use hyphens instead.
Check the list below to figure out the name of the secret(s) you need to set::

* `MAILGUN-API-KEY`
* `MAILJEY-API-KEY`
* `MAILJEY-SECRET-KEY`
* `MANDRILL-API-KEY`
* `POSTMARK-SERVER-TOKEN`
* `SENDGRID-API-KEY`
* `SENDINBLUE-API-KEY`
* `SPARKPOST-API-KEY`

For example, if you're using SendGrid, open the Key Vault in the Azure Portal, select **Secrets**,
and add a `SENDGRID-API-KEY` secret.

To check that the email service works, try signing up as a new user in the app. A verification email 
should be sent to the new user's email address. If no email shows up, check the App Service Log stream
and check the email service provider's logs.

Notes
-----

Caching
+++++++++++++

The project comes with support for caching, using `redis-server` locally and Azure Cache for Redis in production.

Nothing is cached in the generated project, so if you would like to test the cache works,
you need to add caching to a URL, view, or template fragment.

For example, you can append the following cached fragment to `<my project slug>/templates/pages/about.html`::

```
{% block content %}
{% load cache %}
{% cache 500 sidebar %}
  This is the cached block.
{% endcache %}
{% endblock content %}
```

Then re-deploy the app and visit the `/about` page a couple times.

Navigate to the Azure Portal for the App Service and select **SSH** to open a new SSH session.

In that session, run::

```
$ python manage.py shell
```

Inside the Django shell, run this Python::

```
>>> cache.keys('*')
```

You should see a result like `['template.cache.sidebar.d41d8cd98f00b204e9800998ecf8427e']`,
indicating that Redis has a key for the sidebar template fragment in its key/value store.

If you don't see that, you may want to set `IGNORE_EXCEPTIONS` to `False` in `settings/production.py`.

Read the Djangoc cache docs for details on ways to cache.
https://docs.djangoproject.com/en/4.1/topics/cache/


Media storage
+++++++++++++

This project comes with support for media storage using the `django-storages` package.
That package supports many backends, but since you're deploying to Azure, we assume
you also want to store the media in Azure (Blob) Storage.

If you'd like to test out media storage, you need to add an `ImageField` or `FileField`
to the `UserModel`, and expose that field in admin. 

For a minimal change, copy the approach from this `commit`_.

Then re-deploy the app and open Django admin. Select a `User` (creating one if you haven't yet),
and upload an image for that user. Save the model.

Open that same model again and you should see a link to the image file. Click that link
and verify that the URL bar has an Azure storage URL and the browser displays the expected image.

Note that the Storage container is configured for read-only public access.
If you need more secure access restrictions or a CDN in front, you'll need to configure it differently.

https://github.com/pamelafox/cookiecutter-django-output/commit/217dda71cc536eb1c7d60dc6a8cb9c792dd1f320

Celery
+++++++++++++

If you chose to enable Celery in your project, then the deployed app uses Azure Cache for Redis 
as the broker, and lets you schedule tasks in Django Admin thanks to Celery Beat.

When your deployed app starts up, it always starts the `celery` worker at the same time with this command:

```
celery -A config.celery_app worker --loglevel=info --uid=65534 -B
```

To test it out and make sure it's working, you can run the sample `get_users_count` task provided in the project template.

First, navigate to the Azure Portal for the App Service.

Select **Log stream** to watch the logs for the service (which includes `celery` logs and `gunicorn` logs).

In another tab, select **SSH** to start a SSH session on the App Service container.
Inside that session, run::

```
$ python manage.py shell
```

Inside the Django shell, run this Python::

```
>>> from my_awesome_project.users.tasks import get_users_count
>>> get_users_count.delay()
```

You should now see that task processed in the Log stream.

Troubleshooting
+++++++++++++

Read `this blog post`_ for general tips on debugging Django app deployments on Azure App Service.

http://blog.pamelafox.org/2023/01/tips-for-debugging-django-app.html

If you are having problems deploying the app to Azure, we recommend posting on StackOverflow,
the `Azure subreddit`_, or the `MS Python`_ Discord. 