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

* When prompted for `cloud_storage`, select "Azure"
* When prompted for `use_azure`, enter "y"

There is no supported Azure mail provider, so you can select whichever mail provider you are most comfortable with.

Script
------

Follow these steps to deploy the app:

1. Sign up for an [Azure account](https://azure.microsoft.com/free)
2. Install the [Azure Dev CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
3. Provision and deploy all the resources:

```
azd up
```

4. If all goes well, you'll see the app URL displayed. Navigate to that URL in your browser to load the app. 

Notes
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



Troubleshooting